#!/usr/bin/env bash
#
# Installs every tool needed for Part 3: Docker, K3d, kubectl and the
# Argo CD CLI. Safe to re-run: each step is skipped if already present.

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if ! command -v docker >/dev/null 2>&1; then
    echo "==> Installing Docker"
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$(whoami)"
fi

if ! command -v k3d >/dev/null 2>&1; then
    echo "==> Installing K3d"
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "==> Installing kubectl"
    KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o "${BIN_DIR}/kubectl" \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x "${BIN_DIR}/kubectl"
fi

if ! command -v argocd >/dev/null 2>&1; then
    echo "==> Installing Argo CD CLI"
    curl -fsSL -o "${BIN_DIR}/argocd" \
        https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x "${BIN_DIR}/argocd"
fi

echo "==> All tools installed:"
docker --version
k3d --version
kubectl version --client
"${BIN_DIR}/argocd" version --client 2>/dev/null || argocd version --client
