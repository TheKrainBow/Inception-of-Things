CLUSTER_NAME ?= maagosti-iot
PATH := $(HOME)/.local/bin:$(PATH)

.PHONY: install up verify status destroy push-v1 push-v2

install:
	./scripts/install.sh

up:
	./scripts/bootstrap.sh

verify:
	kubectl -n argocd get application playground
	curl --fail --silent --show-error http://localhost:8888/
	@echo

push-v1:
	./scripts/push-image.sh v1

push-v2:
	./scripts/push-image.sh v2

status:
	kubectl -n argocd get applications
	kubectl -n dev get all

destroy:
	k3d cluster delete $(CLUSTER_NAME)
