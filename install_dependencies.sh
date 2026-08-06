#!/usr/bin/env bash
#
# Inception-of-Things (IoT) - mandatory part dependency installer
#
# Installs everything needed on the HOST machine to complete p1, p2 and p3:
#   - VirtualBox        (Vagrant provider, used by p1/p2)
#   - Vagrant           (p1/p2)
#   - kubectl           (p1/p2/p3)
#   - Docker            (required by k3d, p3)
#   - k3d               (p3)
#   - Argo CD CLI       (p3, optional but handy for `argocd app sync/get`)
#
# Target: Debian/Ubuntu based host. Safe to re-run (skips what's already installed).

set -euo pipefail

log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$1"; }

if [[ $EUID -eq 0 ]]; then
    echo "Please run this script as a normal user (it uses sudo where needed), not as root." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This script only supports Debian/Ubuntu (apt-get not found)." >&2
    exit 1
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

log "Updating package index and installing base prerequisites"
sudo apt-get update
sudo apt-get install -y \
    ca-certificates curl wget gnupg lsb-release apt-transport-https software-properties-common

# ---------------------------------------------------------------------------
# VirtualBox
# ---------------------------------------------------------------------------
if command -v vboxmanage >/dev/null 2>&1; then
    log "VirtualBox already installed: $(vboxmanage --version)"
else
    log "Installing VirtualBox"
    sudo apt-get install -y virtualbox virtualbox-dkms || {
        warn "Package 'virtualbox' unavailable for ${CODENAME}, trying Oracle's repository"
        curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc \
            | sudo gpg --dearmor -o /usr/share/keyrings/oracle-virtualbox-2016.gpg
        echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian ${CODENAME} contrib" \
            | sudo tee /etc/apt/sources.list.d/virtualbox.list >/dev/null
        sudo apt-get update
        sudo apt-get install -y virtualbox-7.0
    }
fi

# ---------------------------------------------------------------------------
# Vagrant (HashiCorp official repo)
# ---------------------------------------------------------------------------
if command -v vagrant >/dev/null 2>&1; then
    log "Vagrant already installed: $(vagrant --version)"
else
    log "Installing Vagrant (HashiCorp repository)"
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y vagrant
fi

# ---------------------------------------------------------------------------
# kubectl (official Kubernetes apt repo, latest stable)
# ---------------------------------------------------------------------------
if command -v kubectl >/dev/null 2>&1; then
    log "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    log "Installing kubectl (latest stable)"
    sudo mkdir -p -m 755 /etc/apt/keyrings
    KUBE_LATEST_MINOR="$(curl -fsSL https://dl.k8s.io/release/stable.txt | sed -E 's/^v([0-9]+\.[0-9]+).*/\1/')"
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBE_LATEST_MINOR}/deb/Release.key" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_LATEST_MINOR}/deb/ /" \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y kubectl
fi

# ---------------------------------------------------------------------------
# Docker (required by k3d in p3)
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
    log "Docker already installed: $(docker --version)"
else
    log "Installing Docker Engine (official repository)"
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    warn "Added $USER to the 'docker' group. Log out/in (or run 'newgrp docker') for it to take effect."
fi

# ---------------------------------------------------------------------------
# k3d (p3)
# ---------------------------------------------------------------------------
if command -v k3d >/dev/null 2>&1; then
    log "k3d already installed: $(k3d version | head -1)"
else
    log "Installing k3d"
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# ---------------------------------------------------------------------------
# Argo CD CLI (p3, optional convenience tool)
# ---------------------------------------------------------------------------
if command -v argocd >/dev/null 2>&1; then
    log "Argo CD CLI already installed: $(argocd version --client --short 2>/dev/null || true)"
else
    log "Installing Argo CD CLI (latest release)"
    ARGOCD_VERSION="$(curl -fsSL https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
    curl -fsSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
    sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
    rm -f /tmp/argocd
fi

log "All dependencies installed"
echo "Installed versions:"
echo "  VirtualBox : $(vboxmanage --version 2>/dev/null || echo 'not found')"
echo "  Vagrant    : $(vagrant --version 2>/dev/null || echo 'not found')"
echo "  kubectl    : $(kubectl version --client 2>/dev/null | head -1 || echo 'not found')"
echo "  Docker     : $(docker --version 2>/dev/null || echo 'not found')"
echo "  k3d        : $(k3d version 2>/dev/null | head -1 || echo 'not found')"
echo "  argocd     : $(argocd version --client --short 2>/dev/null || echo 'not found')"

if ! groups "$USER" | grep -q docker; then
    warn "Remember to log out/in for the docker group membership to apply before using k3d (part 3)."
fi
