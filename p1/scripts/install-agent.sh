#!/usr/bin/env bash

set -Eeuo pipefail

: "${K3S_TOKEN:?K3S_TOKEN is required}"
: "${NODE_IP:?NODE_IP is required}"
: "${SERVER_IP:?SERVER_IP is required}"
: "${K3S_NODE_NAME:?K3S_NODE_NAME is required}"

readonly K3S_INSTALL_URL="https://get.k3s.io"

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

wait_for_server() {
	for _ in $(seq 1 150); do
		if timeout 2 bash -c "</dev/tcp/${SERVER_IP}/6443" 2>/dev/null; then
			return 0
		fi
		sleep 2
	done
	echo "K3s server ${SERVER_IP}:6443 did not become reachable in time" >&2
	return 1
}

write_k3s_config() {
	local interface_name="$1"

	install -d -m 0755 /etc/rancher/k3s
	cat >/etc/rancher/k3s/config.yaml <<EOF
server: "https://${SERVER_IP}:6443"
token: "${K3S_TOKEN}"
node-name: "${K3S_NODE_NAME}"
node-ip: "${NODE_IP}"
flannel-iface: "${interface_name}"
EOF
	chmod 0600 /etc/rancher/k3s/config.yaml
}

install_k3s() {
	curl --fail --silent --show-error --location "${K3S_INSTALL_URL}" |
		INSTALL_K3S_CHANNEL=stable sh -s - agent
	if [[ ! -e /usr/local/bin/kubectl ]]; then
		ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
	fi
}

wait_for_agent() {
	for _ in $(seq 1 120); do
		if systemctl is-active --quiet k3s-agent; then
			return 0
		fi
		sleep 2
	done
	echo "K3s agent did not become active in time" >&2
	journalctl -u k3s-agent --no-pager -n 100 >&2
	return 1
}

main() {
	install_prerequisites
	wait_for_server
	write_k3s_config "$(private_interface)"
	install_k3s
	wait_for_agent
	systemctl --no-pager --full status k3s-agent
}

main "$@"
