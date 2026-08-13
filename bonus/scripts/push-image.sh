#!/usr/bin/env bash
#
# Bumps the playground image tag in the in-cluster GitLab "playground"
# project that Argo CD's "playground-gitlab" Application watches, and
# pushes the change. Argo CD's automated sync then picks it up on its own.
# Mints its own short-lived tokens (mirrors bootstrap.sh) since none are
# persisted after the initial seed.

set -euo pipefail

TAG="${1:?Usage: push-image.sh <v1|v2>}"

GITLAB_NS="gitlab"
GITLAB_USER="maagosti"
PROJECT_NAME="playground"
LOCAL_PORT="8929"
TOKEN_EXPIRY="$(date -d '+1 day' +%F)"

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
trap 'kill "${PF_PID}" 2>/dev/null || true; rm -rf "${WORKDIR:-}"' EXIT

until curl -sf "http://localhost:${LOCAL_PORT}/-/readiness" >/dev/null 2>&1; do
    sleep 2
done

echo "==> Minting an API token for '${GITLAB_USER}'"
USER_ID="$(curl -sf --header "PRIVATE-TOKEN: ${ROOT_TOKEN}" \
    "http://localhost:${LOCAL_PORT}/api/v4/users?username=${GITLAB_USER}" | jq -r '.[0].id')"
USER_TOKEN="$(curl -sf --header "PRIVATE-TOKEN: ${ROOT_TOKEN}" -X POST \
    "http://localhost:${LOCAL_PORT}/api/v4/users/${USER_ID}/personal_access_tokens" \
    -d "name=push-image" -d "scopes[]=api" -d "scopes[]=write_repository" \
    -d "expires_at=${TOKEN_EXPIRY}" | jq -r '.token')"

echo "==> Cloning ${PROJECT_NAME}"
WORKDIR="$(mktemp -d)"
git clone --quiet \
    "http://${GITLAB_USER}:${USER_TOKEN}@localhost:${LOCAL_PORT}/${GITLAB_USER}/${PROJECT_NAME}.git" \
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
