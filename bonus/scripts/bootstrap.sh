#!/usr/bin/env bash
#
# Deploys a local GitLab instance into the "gitlab" namespace of the p3
# K3d cluster, creates a dedicated non-root GitLab account, and seeds a
# self-contained manifests repo (owned by that account, not cloned from
# any GitHub source) that a bonus-only Argo CD Application watches.
# p3's own "playground" Application and "dev" namespace are never
# touched, so both parts stay independently deployed and demoable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFS_DIR="${SCRIPT_DIR}/../confs"
PATH="${HOME}/.local/bin:${PATH}"

GITLAB_NS="gitlab"
GITLAB_USER="maagosti"
GITLAB_EMAIL="maagosti@iot.local"
PROJECT_NAME="playground"
LOCAL_PORT="8929"
TOKEN_EXPIRY="$(date -d '+30 days' +%F)"

echo "==> Creating namespace and deploying GitLab"
kubectl apply -f "${CONFS_DIR}/namespace.yaml"
kubectl apply -f "${CONFS_DIR}/gitlab.yaml"

echo "==> Waiting for GitLab to become ready (first boot can take 5-15 minutes)"
kubectl -n "${GITLAB_NS}" wait --for=condition=available --timeout=1200s deployment/gitlab

echo "==> Minting a root API token"
ROOT_TOKEN="$(openssl rand -hex 20)"
kubectl -n "${GITLAB_NS}" exec deploy/gitlab -- gitlab-rails runner "
  token = User.find_by_username('root').personal_access_tokens.find_or_initialize_by(name: 'bootstrap')
  token.scopes = [:api]
  token.expires_at = 30.days.from_now
  token.set_token('${ROOT_TOKEN}')
  token.save!
"

echo "==> Port-forwarding GitLab to localhost:${LOCAL_PORT}"
kubectl -n "${GITLAB_NS}" port-forward svc/gitlab "${LOCAL_PORT}:80" \
    >/tmp/gitlab-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT

until curl -sf "http://localhost:${LOCAL_PORT}/-/readiness" >/dev/null 2>&1; do
    sleep 5
done

echo "==> Creating dedicated non-root account '${GITLAB_USER}'"
USER_PASSWORD="$(openssl rand -base64 24)"
USER_ID="$(curl -sf --header "PRIVATE-TOKEN: ${ROOT_TOKEN}" \
    "http://localhost:${LOCAL_PORT}/api/v4/users?username=${GITLAB_USER}" | jq -r '.[0].id // empty')"
if [ -z "${USER_ID}" ]; then
    USER_ID="$(curl -sf --header "PRIVATE-TOKEN: ${ROOT_TOKEN}" -X POST \
        "http://localhost:${LOCAL_PORT}/api/v4/users" \
        --data-urlencode "username=${GITLAB_USER}" \
        --data-urlencode "name=${GITLAB_USER}" \
        --data-urlencode "email=${GITLAB_EMAIL}" \
        --data-urlencode "password=${USER_PASSWORD}" \
        -d "skip_confirmation=true" -d "admin=false" | jq -r '.id')"
else
    curl -sf --header "PRIVATE-TOKEN: ${ROOT_TOKEN}" -X PUT \
        "http://localhost:${LOCAL_PORT}/api/v4/users/${USER_ID}" \
        --data-urlencode "password=${USER_PASSWORD}" >/dev/null
fi

echo "==> Minting an API token for '${GITLAB_USER}'"
USER_TOKEN="$(curl -sf --header "PRIVATE-TOKEN: ${ROOT_TOKEN}" -X POST \
    "http://localhost:${LOCAL_PORT}/api/v4/users/${USER_ID}/personal_access_tokens" \
    -d "name=bootstrap" -d "scopes[]=api" -d "scopes[]=write_repository" \
    -d "expires_at=${TOKEN_EXPIRY}" | jq -r '.token')"

echo "==> Creating project '${PROJECT_NAME}' owned by '${GITLAB_USER}'"
curl -sf --header "PRIVATE-TOKEN: ${USER_TOKEN}" -X POST \
    "http://localhost:${LOCAL_PORT}/api/v4/projects" \
    -d "name=${PROJECT_NAME}&visibility=public" >/dev/null || true

echo "==> Pushing self-contained manifests (owned by bonus, not p3/GitHub)"
WORKDIR="$(mktemp -d)"
mkdir -p "${WORKDIR}/manifests"
cp "${CONFS_DIR}/deployment.yaml" "${WORKDIR}/manifests/deployment.yaml"
git -C "${WORKDIR}" init --quiet -b main
git -C "${WORKDIR}" add manifests/deployment.yaml
git -C "${WORKDIR}" -c user.email="${GITLAB_EMAIL}" -c user.name="${GITLAB_USER}" \
    commit --quiet -m "Add playground manifests"
git -C "${WORKDIR}" remote add gitlab \
    "http://${GITLAB_USER}:${USER_TOKEN}@localhost:${LOCAL_PORT}/${GITLAB_USER}/${PROJECT_NAME}.git"
git -C "${WORKDIR}" push --quiet --force gitlab HEAD:main
rm -rf "${WORKDIR}"

kill "${PF_PID}" 2>/dev/null || true
trap - EXIT

echo "==> Registering local GitLab as an Argo CD repository"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: http://gitlab.${GITLAB_NS}.svc.cluster.local/${GITLAB_USER}/${PROJECT_NAME}.git
  username: ${GITLAB_USER}
  password: "${USER_TOKEN}"
EOF

echo "==> Deploying the bonus-only Argo CD Application"
kubectl apply -f "${CONFS_DIR}/application.yaml"

echo "==> Waiting for the sync from local GitLab"
for _ in $(seq 1 60); do
    STATUS="$(kubectl -n argocd get application playground-gitlab -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    [ "${STATUS}" = "Synced" ] && break
    sleep 5
done

kubectl -n dev-gitlab get pods

GITLAB_ROOT_PASSWORD="$(kubectl -n "${GITLAB_NS}" exec deploy/gitlab -- grep 'Password:' /etc/gitlab/initial_root_password | awk '{print $2}')"
echo "==> GitLab root password: ${GITLAB_ROOT_PASSWORD}"
echo "==> GitLab account: ${GITLAB_USER} / ${USER_PASSWORD}"
echo "==> Browse GitLab with: kubectl -n gitlab port-forward svc/gitlab 8929:80"

ARGOCD_ADMIN_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"

CREDENTIALS_FILE="${SCRIPT_DIR}/../credentials.txt"
cat > "${CREDENTIALS_FILE}" <<EOF
# Generated by bonus/scripts/bootstrap.sh on $(date -Iseconds)

[GitLab]
URL:           http://localhost:8929 (after: kubectl -n gitlab port-forward svc/gitlab 8929:80)
Root user:     root
Root password: ${GITLAB_ROOT_PASSWORD}
Account user:  ${GITLAB_USER}
Account pass:  ${USER_PASSWORD}

[Argo CD] (from p3, reused by the bonus)
URL:      https://localhost:8080 (after: kubectl -n argocd port-forward svc/argocd-server 8080:443)
Username: admin
Password: ${ARGOCD_ADMIN_PASSWORD:-see p3/credentials.txt}
EOF
echo "==> Credentials written to ${CREDENTIALS_FILE}"
