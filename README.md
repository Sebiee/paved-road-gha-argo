# paved-road-gha-argo

Minimal **GitHub Actions -> GHCR -> Argo CD on kind** paved-road lab.

**This is a lab**, not production. For production GitOps discipline (plan vs apply, real mutate path), point interviewers at **bboxiac**.

```
app/                      tiny Go HTTP service ("OK") + multi-stage Dockerfile
.github/workflows/ci.yml  test + docker build; push to GHCR on main only
gitops/                   kustomize Deployment/Service + Argo Application
Makefile                  kind-up | argo-install | build-local | load-image | demo
```

## Architecture

```
PR/push --> GHA (go test + docker build)
              |
              |-- main only --> push ghcr.io/<owner>/paved-road-app
                                      |
kind cluster <-- Argo CD Application -- (or local image via overlays/kind)
```

## Prerequisites

| Tool | Required for | Install hint |
|------|--------------|--------------|
| Go 1.22+ | local `go test` | optional (CI has it) |
| Docker | `build-local` / `load-image` | Docker Desktop + WSL integration |
| kind | local cluster | https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| Helm 3 | Argo CD install | https://helm.sh/docs/intro/install/ |
| kubectl | everything cluster-side | https://kubernetes.io/docs/tasks/tools/ |

`make` targets **check** for kind/helm/kubectl/docker and print install hints - they do not auto-install.

## Exact demo steps (no AWS, no GHCR required)

From this directory (WSL):

```bash
make help
make kind-up
make argo-install
make build-local
make load-image
make demo
```

Then in another terminal:

```bash
kubectl -n paved-road port-forward svc/paved-road-app 8088:80
curl -s http://127.0.0.1:8088/          # -> OK
curl -s http://127.0.0.1:8088/healthz   # -> ok
```

Tear down:

```bash
make kind-down
```

### Notes on the Argo Application

- `gitops/application.yaml` points at `https://github.com/Sebiee/paved-road-gha-argo` (public). Fork/rename if you copy this lab elsewhere.
- Default Application `path` is `gitops/overlays/kind` (local image `paved-road-app:local`, `imagePullPolicy: Never`).
- `make demo` applies the Application **and** falls back to `kubectl apply -k gitops/overlays/kind` so the demo still works if the repo URL is unreachable.

## CI -> GHCR path (optional)

1. Push this repo to GitHub (public or private).
2. Ensure Actions can write packages: workflow already sets `permissions.packages: write`.  
   Also check **Settings -> Actions -> General -> Workflow permissions -> Read and write**.
3. Merge to `main` -> image at `ghcr.io/<owner>/paved-road-app:latest` (and sha tag).
4. Point kustomize `base` image at your GHCR name; switch Application `path` to `gitops/base`.
5. On private GHCR packages, configure an imagePullSecret / Argo repo credential - **do not commit secrets**.

No long-lived registry passwords are stored in this repo; CI uses `github.actor` + `GITHUB_TOKEN`.

## App

- `GET /` -> `OK`
- `GET /healthz` -> `ok`
- Port `8080` (Service maps `80 -> 8080`)

```bash
cd app && go test ./...
```

## Honesty bar

| Claim | Reality |
|-------|---------|
| Lab proves GHA + container + Argo/kustomize shape | yes, when `make demo` works |
| Production GitOps | **bboxiac**, not this repo |
| Multi-cluster / AWS / sealed-secrets | out of scope by design |
