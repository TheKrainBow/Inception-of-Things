LOGIN ?= tmoragli
VAGRANT := IOT_LOGIN=$(LOGIN) vagrant

.PHONY: up validate status verify resources ssh halt destroy

up:
	$(VAGRANT) up --provider=virtualbox

validate:
	$(VAGRANT) validate

status:
	$(VAGRANT) status

verify:
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
