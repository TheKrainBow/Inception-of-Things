#!/usr/bin/env bash
#
# Bumps the playground image tag in the public maagosti-iot manifests repo
# that Argo CD's "playground" Application watches, and pushes the change.
# Argo CD's automated sync then picks it up on its own.

set -euo pipefail

TAG="${1:?Usage: push-image.sh <v1|v2>}"
REPO="git@github.com:TheKrainBow/maagosti-iot.git"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "==> Cloning maagosti-iot"
git clone --quiet --depth 1 "${REPO}" "${WORKDIR}"

sed -i "s|image: wil42/playground:.*|image: wil42/playground:${TAG}|" \
    "${WORKDIR}/manifests/deployment.yaml"

if git -C "${WORKDIR}" diff --quiet; then
    echo "==> manifests/deployment.yaml is already on ${TAG}, nothing to push"
    exit 0
fi

git -C "${WORKDIR}" add manifests/deployment.yaml
git -C "${WORKDIR}" commit --quiet -m "Set playground image to ${TAG}"
git -C "${WORKDIR}" push --quiet origin HEAD

echo "==> Pushed wil42/playground:${TAG} to maagosti-iot"
