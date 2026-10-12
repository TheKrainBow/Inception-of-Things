CLUSTER_NAME ?= maagosti-iot
PATH := $(HOME)/.local/bin:$(PATH)

.PHONY: install up verify status port-forward gitlab-ui argocd-ui destroy push-v1 push-v2

install:
	./scripts/install.sh

up:
	./scripts/bootstrap.sh

verify:
	CLUSTER_NAME=$(CLUSTER_NAME) ./scripts/verify.sh

push-v1:
	./scripts/push-image.sh v1

push-v2:
	./scripts/push-image.sh v2

status:
	kubectl -n gitlab get pods,pvc
	kubectl -n dev-gitlab get all

port-forward:
	kubectl -n dev-gitlab port-forward svc/playground 8890:8888

gitlab-ui:
	@echo "GitLab UI: http://localhost:8929 (see credentials.txt), Ctrl-C to stop"
	kubectl -n gitlab port-forward svc/gitlab 8929:80

argocd-ui:
	@echo "Argo CD UI: https://localhost:8080 (admin / see credentials.txt), Ctrl-C to stop"
	kubectl -n argocd port-forward svc/argocd-server 8080:443

destroy:
	kubectl delete -f confs/application.yaml --ignore-not-found
	kubectl -n argocd delete secret gitlab-repo --ignore-not-found
	kubectl delete namespace dev-gitlab --ignore-not-found
	kubectl delete namespace gitlab --ignore-not-found
