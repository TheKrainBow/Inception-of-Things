#!/usr/bin/env bash
#
# Walks through every check needed to prove Part 3 works, step by step,
# then prints where Argo CD lives and how to log in.

set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-maagosti-iot}"
PATH="${HOME}/.local/bin:${PATH}"
FAILED=0

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m[OK]\033[0m %s\n' "$1"; }
ko()   { printf '\033[31m[KO]\033[0m %s\n' "$1"; FAILED=1; }

step "1. K3d cluster ${CLUSTER_NAME} exists"
if k3d cluster list "${CLUSTER_NAME}" >/dev/null 2>&1; then
    k3d cluster list "${CLUSTER_NAME}"
    ok "cluster found"
else
    ko "cluster not found, run: make up"
    exit 1
fi

step "2. kubectl points at the cluster"
CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [ "${CONTEXT}" = "k3d-${CLUSTER_NAME}" ]; then
    ok "current context: ${CONTEXT}"
else
    ko "current context is '${CONTEXT}', run: kubectl config use-context k3d-${CLUSTER_NAME}"
fi

step "3. Namespaces argocd and dev exist"
kubectl get namespace argocd dev && ok "both namespaces present" || ko "missing namespace"

step "4. Argo CD pods are running (namespace argocd)"
kubectl -n argocd get pods
NOT_READY="$(kubectl -n argocd get pods --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed"' | wc -l)"
[ "${NOT_READY}" -eq 0 ] && ok "all Argo CD pods running" || ko "${NOT_READY} Argo CD pod(s) not running"

step "5. Argo CD Application 'playground' is Synced and Healthy"
kubectl -n argocd get application playground
SYNC="$(kubectl -n argocd get application playground -o jsonpath='{.status.sync.status}' 2>/dev/null)"
HEALTH="$(kubectl -n argocd get application playground -o jsonpath='{.status.health.status}' 2>/dev/null)"
REPO="$(kubectl -n argocd get application playground -o jsonpath='{.spec.source.repoURL} (path: {.spec.source.path})' 2>/dev/null)"
echo "Source repo: ${REPO}"
[ "${SYNC}" = "Synced" ] && [ "${HEALTH}" = "Healthy" ] \
    && ok "Synced / Healthy" || ko "sync=${SYNC:-?} health=${HEALTH:-?}"

step "6. App resources deployed in namespace dev"
kubectl -n dev get deployments,services,pods -o wide
IMAGE="$(kubectl -n dev get deployments -o jsonpath='{.items[*].spec.template.spec.containers[*].image}' 2>/dev/null)"
echo "Running image: ${IMAGE:-?}"
[ -n "${IMAGE}" ] && ok "deployment present" || ko "no deployment in dev"

step "7. App answers on http://localhost:8888/"
if RESPONSE="$(curl --fail --silent --show-error --max-time 5 http://localhost:8888/)"; then
    echo "${RESPONSE}"
    ok "app reachable"
else
    ko "app not reachable on localhost:8888"
fi

PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"

step "Where is Argo CD?"
cat <<EOF
Argo CD runs inside the cluster, namespace 'argocd', service 'argocd-server'.
It is not exposed on the host, so open a port-forward in another terminal:

    make ui     (= kubectl -n argocd port-forward svc/argocd-server 8080:443)

Then browse to https://localhost:8080 (accept the self-signed certificate)
    Username: admin
    Password: ${PASSWORD:-<not found>}

In the UI, the 'playground' tile should show Synced / Healthy; click it to see
the Deployment, Service and Pod it manages in the 'dev' namespace.
EOF

step "Test continuous deployment (v1 -> v2)"
cat <<EOF
    make push-v2        # bumps the image tag in the GitHub repo and pushes
    # wait ~30s-1min (Argo CD polls every 30s), or click REFRESH in the UI
    make verify         # step 7 should now answer "message": "v2"
    make push-v1        # roll back
EOF

echo
if [ "${FAILED}" -eq 0 ]; then
    printf '\033[32mAll checks passed.\033[0m\n'
else
    printf '\033[31mSome checks failed, see [KO] lines above.\033[0m\n'
fi
exit "${FAILED}"
