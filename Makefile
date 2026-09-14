.RECIPEPREFIX := >
CLUSTER_NAME ?= paved-road
ARGO_NS      ?= argocd
APP_NS       ?= paved-road
IMAGE_LOCAL  ?= paved-road-app:local
HELM_RELEASE ?= argo-cd

.PHONY: help kind-up kind-down argo-install demo build-local load-image check-kind check-helm check-kubectl check-docker

help:
>@echo "paved-road-gha-argo - local GHA->GHCR->Argo-on-kind lab"
>@echo ""
>@echo "  make kind-up       Create kind cluster ($(CLUSTER_NAME))"
>@echo "  make argo-install  Install Argo CD via Helm into $(ARGO_NS)"
>@echo "  make build-local   Build Go binary image for kind (docker)"
>@echo "  make load-image    kind load docker-image $(IMAGE_LOCAL)"
>@echo "  make demo          Apply Application, wait for sync, print curl"
>@echo "  make kind-down     Delete kind cluster"
>@echo ""
>@echo "Typical demo path (no GHCR required):"
>@echo "  make kind-up && make argo-install && make build-local && make load-image && make demo"
>@echo ""
>@echo "Honesty: this is a lab. Production GitOps example = bboxiac."

check-kind:
>@command -v kind >/dev/null 2>&1 || { \
>  echo "ERROR: kind not found."; \
>  echo "Install: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"; \
>  echo "  # example (linux amd64):"; \
>  echo "  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"; \
>  exit 1; \
>}

check-helm:
>@command -v helm >/dev/null 2>&1 || { \
>  echo "ERROR: helm not found."; \
>  echo "Install: https://helm.sh/docs/intro/install/"; \
>  echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"; \
>  exit 1; \
>}

check-kubectl:
>@command -v kubectl >/dev/null 2>&1 || { \
>  echo "ERROR: kubectl not found."; \
>  echo "Install: https://kubernetes.io/docs/tasks/tools/"; \
>  exit 1; \
>}

check-docker:
>@command -v docker >/dev/null 2>&1 || { \
>  echo "ERROR: docker not found (needed to build/load the local image)."; \
>  echo "Install Docker Engine or Docker Desktop + enable WSL integration."; \
>  exit 1; \
>}

kind-up: check-kind
>@if kind get clusters 2>/dev/null | grep -qx '$(CLUSTER_NAME)'; then \
>  echo "kind cluster '$(CLUSTER_NAME)' already exists"; \
>else \
>  kind create cluster --name $(CLUSTER_NAME); \
>fi
>@kubectl cluster-info --context kind-$(CLUSTER_NAME)

kind-down: check-kind
>kind delete cluster --name $(CLUSTER_NAME)

argo-install: check-helm check-kubectl
>helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
>helm repo update argo
>helm upgrade --install $(HELM_RELEASE) argo/argo-cd \
>  --namespace $(ARGO_NS) --create-namespace \
>  --set configs.params.server\.insecure=true \
>  --set server.service.type=ClusterIP \
>  --wait --timeout 5m
>@echo ""
>@echo "Argo CD installed. Initial admin password:"
>@echo "  kubectl -n $(ARGO_NS) get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
>@echo "Port-forward UI (optional):"
>@echo "  kubectl -n $(ARGO_NS) port-forward svc/$(HELM_RELEASE)-argocd-server 8080:443"

build-local: check-docker
>docker build -t $(IMAGE_LOCAL) ./app

load-image: check-kind check-docker
>kind load docker-image $(IMAGE_LOCAL) --name $(CLUSTER_NAME)

demo: check-kubectl
>@echo "==> Applying Argo CD Application (gitops/application.yaml)"
>@echo "    NOTE: repoURL must be reachable by the cluster (public fork or kind + local path workaround)."
>@echo "    For a fully offline demo without git fetch, apply the kustomize overlay directly:"
>@echo "      kubectl apply -k gitops/overlays/kind"
>@echo ""
>@# Prefer applying Application if Argo is present; always offer direct apply fallback.
>@if kubectl get ns $(ARGO_NS) >/dev/null 2>&1; then \
>  kubectl apply -f gitops/application.yaml; \
>  echo "Waiting up to 120s for Application to become Synced/Healthy (may fail if repoURL unreachable)..."; \
>  kubectl -n $(ARGO_NS) wait --for=jsonpath='{.status.sync.status}'=Synced application/paved-road-app --timeout=120s 2>/dev/null || \
>    echo "WARN: Application not Synced yet (check repoURL / network). Falling back to direct apply."; \
>  kubectl apply -k gitops/overlays/kind; \
>else \
>  echo "Argo CD namespace missing - applying manifests directly."; \
>  kubectl apply -k gitops/overlays/kind; \
>fi
>@kubectl -n $(APP_NS) rollout status deploy/paved-road-app --timeout=120s || true
>@echo ""
>@echo "==> Curl the app (port-forward):"
>@echo "  kubectl -n $(APP_NS) port-forward svc/paved-road-app 8088:80"
>@echo "  curl -s http://127.0.0.1:8088/     # expect: OK"
>@echo "  curl -s http://127.0.0.1:8088/healthz"
