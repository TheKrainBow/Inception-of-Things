CLUSTER_NAME ?= maagosti-iot
PATH := $(HOME)/.local/bin:$(PATH)

.PHONY: install up verify ui status destroy push-v1 push-v2

install:
	./scripts/install.sh

up:
	./scripts/bootstrap.sh

verify:
	CLUSTER_NAME=$(CLUSTER_NAME) ./scripts/verify.sh

ui:
	@echo "Argo CD UI: https://localhost:8080 (admin / see credentials.txt), Ctrl-C to stop"
	kubectl -n argocd port-forward svc/argocd-server 8080:443

push-v1:
	./scripts/push-image.sh v1

push-v2:
	./scripts/push-image.sh v2

status:
	kubectl -n argocd get applications
	kubectl -n dev get all

destroy:
	k3d cluster delete $(CLUSTER_NAME)
