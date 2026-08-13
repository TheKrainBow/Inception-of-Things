#!/usr/bin/env bash
#
# Bumps the playground image tag in the in-cluster GitLab "playground"
# project that Argo CD's "playground-gitlab" Application watches, and
# pushes the change. Argo CD's automated sync then picks it up on its own.
# Asks for the GitLab account password (set during bootstrap.sh) and uses
# it directly for Git's HTTP auth, since no long-lived token is persisted
# after the initial seed. Pushing as the account itself (rather than root)
# is required: it's the Owner of "playground", and root has no membership
# on the project, so root can authenticate but is refused by the protected
# "main" branch.

set -euo pipefail

TAG="${1:?Usage: push-image.sh <v1|v2>}"

GITLAB_NS="gitlab"
GITLAB_USER="maagosti"
PROJECT_NAME="playground"
LOCAL_PORT="8929"

read -r -p "GitLab '${GITLAB_USER}' account password: " GITLAB_PASSWORD

echo "==> Port-forwarding GitLab to localhost:${LOCAL_PORT}"
kubectl -n "${GITLAB_NS}" port-forward svc/gitlab "${LOCAL_PORT}:80" \
    >/tmp/gitlab-port-forward.log 2>&1 &
PF_PID=$!

GIT_ASKPASS="$(mktemp)"
chmod +x "${GIT_ASKPASS}"
cat > "${GIT_ASKPASS}" <<'EOF'
#!/bin/sh
echo "${GITLAB_PASSWORD}"
EOF
export GIT_ASKPASS="${GIT_ASKPASS}"
export GITLAB_PASSWORD

trap 'kill "${PF_PID}" 2>/dev/null || true; rm -f "${GIT_ASKPASS}"; rm -rf "${WORKDIR:-}"' EXIT

until curl -sf "http://localhost:${LOCAL_PORT}/-/readiness" >/dev/null 2>&1; do
    sleep 2
done

echo "==> Cloning ${PROJECT_NAME}"
WORKDIR="$(mktemp -d)"
git clone --quiet \
    "http://${GITLAB_USER}@localhost:${LOCAL_PORT}/${GITLAB_USER}/${PROJECT_NAME}.git" \
    "${WORKDIR}"

sed -i "s|image: wil42/playground:.*|image: wil42/playground:${TAG}|" \
    "${WORKDIR}/manifests/deployment.yaml"

if git -C "${WORKDIR}" diff --quiet; then
    echo "==> manifests/deployment.yaml is already on ${TAG}, nothing to push"
    exit 0
fi

git -C "${WORKDIR}" add manifests/deployment.yaml
git -C "${WORKDIR}" -c user.email="${GITLAB_USER}@iot.local" -c user.name="${GITLAB_USER}" \
    commit --quiet -m "Set playground image to ${TAG}"
git -C "${WORKDIR}" push --quiet origin HEAD:main

echo "==> Pushed wil42/playground:${TAG} to the GitLab playground project"
