#!/usr/bin/env bash

set -Eeuo pipefail

: "${MANIFEST_PATH:?MANIFEST_PATH is required}"
: "${SERVER_IP:?SERVER_IP is required}"

readonly KUBECTL="/usr/local/bin/kubectl"

wait_for_resource() {
	local namespace="$1"
	local resource="$2"

	for _ in $(seq 1 120); do
		if "${KUBECTL}" --namespace "${namespace}" get "${resource}" >/dev/null 2>&1; then
			return 0
		fi
		sleep 2
	done
	echo "Timed out waiting for ${namespace}/${resource}" >&2
	return 1
}

wait_for_http_route() {
	local host="$1"
	local marker="$2"

	for _ in $(seq 1 120); do
		if curl --fail --silent --show-error \
			--header "Host: ${host}" \
			"http://${SERVER_IP}/" 2>/dev/null | grep --quiet "${marker}"; then
			return 0
		fi
		sleep 2
	done
	echo "Route for ${host} did not return ${marker}" >&2
	return 1
}

main() {
	if [[ ! -r "${MANIFEST_PATH}" ]]; then
		echo "Cannot read Kubernetes manifest: ${MANIFEST_PATH}" >&2
		exit 1
	fi

	wait_for_resource kube-system deployment/traefik
	"${KUBECTL}" --namespace kube-system rollout status deployment/traefik --timeout=300s
	"${KUBECTL}" apply --filename "${MANIFEST_PATH}"

	for app in app1 app2 app3; do
		"${KUBECTL}" rollout status "deployment/${app}" --timeout=300s
	done

	wait_for_http_route app1.com 'id="app-1"'
	wait_for_http_route app2.com 'id="app-2"'
	wait_for_http_route unknown.example 'id="app-3"'

	"${KUBECTL}" get deployments,pods,services,ingresses -o wide
	printf '\nAll Part 2 routes passed their smoke tests.\n'
}

main "$@"

