#!/usr/bin/env bash
#
# Sanity-checks the tools this bonus needs. Docker, K3d, kubectl and the
# Argo CD CLI are already installed by p3/scripts/install.sh; GitLab itself
# runs as a workload inside the existing K3d cluster, so nothing extra has
# to be installed on the host.

set -euo pipefail

for bin in docker k3d kubectl curl git jq openssl; do
    command -v "${bin}" >/dev/null 2>&1 || {
        echo "Missing required tool: ${bin} (run p3/scripts/install.sh first)" >&2
        exit 1
    }
done

k3d cluster list maagosti-iot >/dev/null 2>&1 || {
    echo "K3d cluster 'maagosti-iot' not found (run p3/scripts/bootstrap.sh first)" >&2
    exit 1
}

kubectl get storageclass local-path >/dev/null 2>&1 || \
    echo "Warning: no 'local-path' StorageClass found; GitLab's PVC may not bind." >&2

echo "==> All prerequisites present."
