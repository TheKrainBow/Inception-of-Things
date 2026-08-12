#!/usr/bin/env bash

set -Eeuo pipefail

: "${NODE_IP:?NODE_IP is required}"
: "${K3S_NODE_NAME:?K3S_NODE_NAME is required}"

readonly K3S_INSTALL_URL="https://get.k3s.io"
readonly VAGRANT_USER="vagrant"

install_prerequisites() {
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y --no-install-recommends ca-certificates curl
}

private_interface() {
	local interface_name

	interface_name="$(ip -o -4 addr show | awk -v ip="${NODE_IP}" 'index($4, ip "/") == 1 { print $2; exit }')"
	if [[ -z "${interface_name}" ]]; then
		echo "No interface owns ${NODE_IP}" >&2
		ip -brief address >&2
		exit 1
	fi
	printf '%s\n' "${interface_name}"
}

write_k3s_config() {
	local interface_name="$1"

	install -d -m 0755 /etc/rancher/k3s
	cat >/etc/rancher/k3s/config.yaml <<EOF
node-ip: "${NODE_IP}"
node-name: "${K3S_NODE_NAME}"
advertise-address: "${NODE_IP}"
tls-san:
  - "${NODE_IP}"
flannel-iface: "${interface_name}"
write-kubeconfig-mode: "0644"
EOF
	chmod 0600 /etc/rancher/k3s/config.yaml
}

install_k3s() {
	curl --fail --silent --show-error --location "${K3S_INSTALL_URL}" |
		INSTALL_K3S_CHANNEL=stable sh -s - server
}

configure_kubectl_for_vagrant() {
	install -d -m 0700 -o "${VAGRANT_USER}" -g "${VAGRANT_USER}" "/home/${VAGRANT_USER}/.kube"
	install -m 0600 -o "${VAGRANT_USER}" -g "${VAGRANT_USER}" \
		/etc/rancher/k3s/k3s.yaml "/home/${VAGRANT_USER}/.kube/config"
	ln -sfn /usr/local/bin/kubectl /usr/local/bin/k
}

wait_for_server() {
	for _ in $(seq 1 120); do
		if /usr/local/bin/kubectl get --raw=/readyz >/dev/null 2>&1; then
			return 0
		fi
		sleep 2
	done
	echo "K3s API did not become ready in time" >&2
	journalctl -u k3s --no-pager -n 100 >&2
	return 1
}

main() {
	install_prerequisites
	write_k3s_config "$(private_interface)"
	install_k3s
	wait_for_server
	configure_kubectl_for_vagrant
	/usr/local/bin/kubectl get nodes -o wide
}

main "$@"
