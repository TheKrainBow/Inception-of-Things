LOGIN ?= tmoragli
VAGRANT := IOT_LOGIN=$(LOGIN) vagrant

.PHONY: up validate status verify ssh-server ssh-worker halt destroy

up:
	$(VAGRANT) up --provider=virtualbox

validate:
	$(VAGRANT) validate --ignore-provider

status:
	$(VAGRANT) status

verify:
	$(VAGRANT) ssh $(LOGIN)S -c "sudo k3s kubectl wait --for=condition=Ready node/$(LOGIN)s node/$(LOGIN)sw --timeout=180s && sudo k3s kubectl get nodes -o wide"

ssh-server:
	$(VAGRANT) ssh $(LOGIN)S

ssh-worker:
	$(VAGRANT) ssh $(LOGIN)SW

halt:
	$(VAGRANT) halt

destroy:
	$(VAGRANT) destroy -f
