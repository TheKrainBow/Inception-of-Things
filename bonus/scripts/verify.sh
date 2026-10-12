#!/usr/bin/env bash
#
# Walks through every check needed to prove the bonus works, step by step:
# in-cluster GitLab, the repo Argo CD watches, the playground-gitlab
# Application and the app it deploys. Then prints where GitLab and Argo CD
# live and how to log in.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-maagosti-iot}"
PATH="${HOME}/.local/bin:${PATH}"
GITLAB_USER="maagosti"
PROJECT_NAME="playground"
# Dedicated ports so verify never collides with make gitlab-ui/port-forward.
GITLAB_PORT="18929"
APP_PORT="18890"
FAILED=0
PF_PIDS=()

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m[OK]\033[0m %s\n' "$1"; }
ko()   { printf '\033[31m[KO]\033[0m %s\n' "$1"; FAILED=1; }

trap 'for pid in "${PF_PIDS[@]}"; do kill "${pid}" 2>/dev/null; done' EXIT

# port_forward <namespace> <svc> <local>:<remote> <url to poll>
port_forward() {
    kubectl -n "$1" port-forward "svc/$2" "$3" >/dev/null 2>&1 &
    PF_PIDS+=("$!")
    for _ in $(seq 1 20); do
        curl -s --max-time 2 -o /dev/null "$4" && return 0
        sleep 0.5
    done
    return 1
}

step "1. K3d cluster ${CLUSTER_NAME} (from p3) exists"
if k3d cluster list "${CLUSTER_NAME}" >/dev/null 2>&1; then
    k3d cluster list "${CLUSTER_NAME}"
    ok "cluster found"
else
    ko "cluster not found, run p3 first: cd ../p3 && make up"
    exit 1
fi

step "2. kubectl points at the cluster"
CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [ "${CONTEXT}" = "k3d-${CLUSTER_NAME}" ]; then
    ok "current context: ${CONTEXT}"
else
    ko "current context is '${CONTEXT}', run: kubectl config use-context k3d-${CLUSTER_NAME}"
fi

step "3. Namespaces argocd, gitlab and dev-gitlab exist"
kubectl get namespace argocd gitlab dev-gitlab && ok "all namespaces present" || ko "missing namespace"

step "4. GitLab pod is ready and its storage is bound (namespace gitlab)"
kubectl -n gitlab get pods,pvc
GITLAB_READY="$(kubectl -n gitlab get deployment gitlab -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
PVC_PHASE="$(kubectl -n gitlab get pvc gitlab-data -o jsonpath='{.status.phase}' 2>/dev/null)"
[ "${GITLAB_READY:-0}" -ge 1 ] && ok "GitLab pod ready" || ko "GitLab pod not ready (first boot takes 5-15 min)"
[ "${PVC_PHASE}" = "Bound" ] && ok "PVC gitlab-data Bound" || ko "PVC gitlab-data is '${PVC_PHASE:-missing}'"

step "5. GitLab answers and hosts ${GITLAB_USER}/${PROJECT_NAME}"
GITLAB_URL="http://localhost:${GITLAB_PORT}"
REPO_IMAGE=""
if port_forward gitlab gitlab "${GITLAB_PORT}:80" "${GITLAB_URL}/-/readiness"; then
    ok "GitLab reachable (readiness endpoint answers)"
    PROJECT="$(curl -sf "${GITLAB_URL}/api/v4/projects/${GITLAB_USER}%2F${PROJECT_NAME}" 2>/dev/null)"
    if [ -n "${PROJECT}" ]; then
        echo "Project: $(echo "${PROJECT}" | jq -r '.web_url') (visibility: $(echo "${PROJECT}" | jq -r '.visibility'))"
        ok "project ${GITLAB_USER}/${PROJECT_NAME} exists"
    else
        ko "project ${GITLAB_USER}/${PROJECT_NAME} not found"
    fi
    REPO_IMAGE="$(curl -sf "${GITLAB_URL}/${GITLAB_USER}/${PROJECT_NAME}/-/raw/main/manifests/deployment.yaml" 2>/dev/null \
        | awk '/image:/ {print $2; exit}')"
    echo "Image in GitLab repo (manifests/deployment.yaml): ${REPO_IMAGE:-?}"
    [ -n "${REPO_IMAGE}" ] && ok "manifest readable from GitLab" || ko "manifests/deployment.yaml not readable"
else
    ko "GitLab not reachable through port-forward"
fi

step "6. Argo CD knows the GitLab repository (secret argocd/gitlab-repo)"
if kubectl -n argocd get secret gitlab-repo >/dev/null 2>&1; then
    echo "Repo URL: $(kubectl -n argocd get secret gitlab-repo -o jsonpath='{.data.url}' | base64 -d)"
    ok "repository secret present"
else
    ko "secret gitlab-repo missing, run: make up"
fi

step "7. Argo CD pods are running (namespace argocd)"
kubectl -n argocd get pods
NOT_READY="$(kubectl -n argocd get pods --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed"' | wc -l)"
[ "${NOT_READY}" -eq 0 ] && ok "all Argo CD pods running" || ko "${NOT_READY} Argo CD pod(s) not running"

step "8. Argo CD Application 'playground-gitlab' is Synced and Healthy"
kubectl -n argocd get application playground-gitlab
SYNC="$(kubectl -n argocd get application playground-gitlab -o jsonpath='{.status.sync.status}' 2>/dev/null)"
HEALTH="$(kubectl -n argocd get application playground-gitlab -o jsonpath='{.status.health.status}' 2>/dev/null)"
REPO="$(kubectl -n argocd get application playground-gitlab -o jsonpath='{.spec.source.repoURL} (path: {.spec.source.path})' 2>/dev/null)"
echo "Source repo: ${REPO}"
[ "${SYNC}" = "Synced" ] && [ "${HEALTH}" = "Healthy" ] \
    && ok "Synced / Healthy" || ko "sync=${SYNC:-?} health=${HEALTH:-?}"

step "9. App resources deployed in namespace dev-gitlab"
kubectl -n dev-gitlab get deployments,services,pods -o wide
IMAGE="$(kubectl -n dev-gitlab get deployments -o jsonpath='{.items[*].spec.template.spec.containers[*].image}' 2>/dev/null)"
echo "Running image: ${IMAGE:-?}"
if [ -z "${IMAGE}" ]; then
    ko "no deployment in dev-gitlab"
elif [ -n "${REPO_IMAGE}" ] && [ "${IMAGE}" != "${REPO_IMAGE}" ]; then
    ko "cluster runs ${IMAGE} but GitLab says ${REPO_IMAGE} (sync pending? wait ~30s)"
else
    ok "deployment present and matches the GitLab repo"
fi

step "10. App answers (svc dev-gitlab/playground via port-forward)"
if port_forward dev-gitlab playground "${APP_PORT}:8888" "http://localhost:${APP_PORT}/" \
    && RESPONSE="$(curl --fail --silent --show-error --max-time 5 "http://localhost:${APP_PORT}/")"; then
    echo "${RESPONSE}"
    ok "app reachable"
else
    ko "app not reachable"
fi

step "11. Part 3 is left untouched"
P3_SYNC="$(kubectl -n argocd get application playground -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)"
if P3_RESPONSE="$(curl --fail --silent --max-time 5 http://localhost:8888/)"; then
    echo "p3 'playground' (GitHub): ${P3_SYNC:-?}, localhost:8888 -> ${P3_RESPONSE}"
    ok "p3 app still running alongside"
else
    ko "p3 app not reachable on localhost:8888 (${P3_SYNC:-Application missing})"
fi

GITLAB_ROOT_PASSWORD="$(kubectl -n gitlab exec deploy/gitlab -- grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | awk '{print $2}')"
GITLAB_USER_PASSWORD="$(awk '/^Account pass:/ {print $3}' "${SCRIPT_DIR}/../credentials.txt" 2>/dev/null)"
ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"

step "Where is GitLab?"
cat <<EOF
GitLab runs inside the cluster, namespace 'gitlab', service 'gitlab'.
Open a port-forward in another terminal:

    make gitlab-ui     (= kubectl -n gitlab port-forward svc/gitlab 8929:80)

Then browse to http://localhost:8929
    root     / ${GITLAB_ROOT_PASSWORD:-<see credentials.txt>}
    ${GITLAB_USER} / ${GITLAB_USER_PASSWORD:-<see credentials.txt>}

Project ${GITLAB_USER}/${PROJECT_NAME} holds manifests/deployment.yaml, the
file Argo CD syncs from.
EOF

step "Where is Argo CD?"
cat <<EOF
Same Argo CD as p3: namespace 'argocd', service 'argocd-server'.

    make argocd-ui     (= kubectl -n argocd port-forward svc/argocd-server 8080:443)

Then browse to https://localhost:8080 (accept the self-signed certificate)
    Username: admin
    Password: ${ARGOCD_PASSWORD:-<not found>}

Two tiles should be Synced / Healthy: 'playground' (GitHub, p3) and
'playground-gitlab' (local GitLab, bonus).
EOF

step "Test continuous deployment from GitLab"
cat <<EOF
    make push-v1        # asks the ${GITLAB_USER} password, pushes the tag to GitLab
    # wait ~30s-1min (Argo CD polls every 30s), or click REFRESH in the UI
    make verify         # step 10 should now answer the new "message"
    make push-v2        # switch back
EOF

echo
if [ "${FAILED}" -eq 0 ]; then
    printf '\033[32mAll checks passed.\033[0m\n'
else
    printf '\033[31mSome checks failed, see [KO] lines above.\033[0m\n'
fi
exit "${FAILED}"
