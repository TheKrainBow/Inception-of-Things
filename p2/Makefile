LOGIN ?= tmoragli
VAGRANT := IOT_LOGIN=$(LOGIN) vagrant
SERVER_IP := 192.168.56.110
APP_HOSTS := app1.com app2.com

.PHONY: up hosts validate status verify resources ssh halt destroy

up: hosts
	$(VAGRANT) up --provider=virtualbox

hosts:
	@if ! grep -Eq '^[[:space:]]*$(SERVER_IP)[[:space:]]+([^#]*[[:space:]])?app1\.com([[:space:]]|$$)' /etc/hosts \
		|| ! grep -Eq '^[[:space:]]*$(SERVER_IP)[[:space:]]+([^#]*[[:space:]])?app2\.com([[:space:]]|$$)' /etc/hosts; then \
		echo "$(SERVER_IP) $(APP_HOSTS)" | sudo tee -a /etc/hosts >/dev/null; \
	else \
		echo "Host mappings already configured for $(APP_HOSTS)"; \
	fi

validate:
	$(VAGRANT) validate --ignore-provider

status:
	$(VAGRANT) status

verify:
	$(VAGRANT) ssh $(LOGIN)S -c "kubectl rollout status deployment/app1 --timeout=180s && kubectl rollout status deployment/app2 --timeout=180s && kubectl rollout status deployment/app3 --timeout=180s && kubectl get deployment/app1 -o jsonpath='{.spec.replicas}:{.status.readyReplicas}' | grep -qx '1:1' && kubectl get deployment/app2 -o jsonpath='{.spec.replicas}:{.status.readyReplicas}' | grep -qx '3:3' && kubectl get deployment/app3 -o jsonpath='{.spec.replicas}:{.status.readyReplicas}' | grep -qx '1:1'"
	curl --fail --silent --show-error -H "Host: app1.com" http://192.168.56.110/ | grep 'id="app-1"'
	curl --fail --silent --show-error -H "Host: app2.com" http://192.168.56.110/ | grep 'id="app-2"'
	curl --fail --silent --show-error -H "Host: anything.invalid" http://192.168.56.110/ | grep 'id="app-3"'

resources:
	$(VAGRANT) ssh $(LOGIN)S -c "kubectl get deployments,pods,services,ingresses -o wide"

ssh:
	$(VAGRANT) ssh $(LOGIN)S

halt:
	$(VAGRANT) halt

destroy:
	$(VAGRANT) destroy -f
