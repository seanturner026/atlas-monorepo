set quiet

KIND_CLUSTER := "atlas-local"
ATLAS_IMAGE := "arigaio/atlas:latest"
ATLAS := 'docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo -w /repo arigaio/atlas:latest'

[private]
default:
    just --list --alias-style left --list-heading ''

# cluster
# -------------------------------------------------------------------
[doc('Bring up the kind cluster, install ArgoCD, apply the root App. Idempotent.')]
[group('cluster')]
up:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! kind get clusters | grep -qx "{{ KIND_CLUSTER }}"; then
      kind create cluster --name "{{ KIND_CLUSTER }}"
    fi
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kustomize build k8s/apps/argocd/overlays/production | kubectl apply -f -
    kubectl wait --for=condition=available --timeout=300s deploy/argocd-server -n argocd
    kubectl apply -f k8s/cluster/production/app.yaml

[doc('Delete the kind cluster.')]
[group('cluster')]
[confirm('Delete kind cluster {{ KIND_CLUSTER }}?')]
down:
    kind delete cluster --name "{{ KIND_CLUSTER }}"

[doc('Print the ArgoCD initial admin password.')]
[group('cluster')]
argocd-password:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode
    echo

[doc('Print the admin password and port-forward argocd-server on https://localhost:8080.')]
[group('cluster')]
argocd-ui: argocd-password
    kubectl port-forward svc/argocd-server -n argocd 8080:443

# db
# -------------------------------------------------------------------
[doc('Scaffold a new database directory under db/<NAME>/.')]
[group('db')]
new NAME:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -e "db/{{ NAME }}" ]; then
      echo "db/{{ NAME }} already exists" >&2
      exit 1
    fi
    mkdir -p \
      "db/{{ NAME }}/migrations" \
      "db/{{ NAME }}/k8s/resources" \
      "db/{{ NAME }}/k8s/overlays/production"
    echo "scaffolded db/{{ NAME }} — copy resources/ + overlays/production/ from db/db1/ as a starting point"

# migrate
# -------------------------------------------------------------------
[doc('Create a new migration file under db/<SVC>/migrations.')]
[group('migrate')]
migrate-new SVC NAME:
    {{ ATLAS }} migrate new --dir file://db/{{ SVC }}/migrations {{ NAME }}

[doc('Recompute atlas.sum for db/<SVC>/migrations.')]
[group('migrate')]
migrate-hash SVC:
    {{ ATLAS }} migrate hash --dir file://db/{{ SVC }}/migrations

[doc('Lint migrations. Requires atlas installed locally (brew install ariga/tap/atlas) — needs docker-in-docker for the dev container.')]
[group('migrate')]
migrate-lint SVC:
    atlas migrate lint --dir file://db/{{ SVC }}/migrations --dev-url docker://postgres/16/dev

# build
# -------------------------------------------------------------------
[doc('Build per-db images and load into kind. Pass SVC to limit, omit to build all dbs.')]
[group('build')]
build SVC='':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ SVC }}" ]; then
      services=("{{ SVC }}")
    else
      services=()
      for d in db/*/; do
        services+=("$(basename "$d")")
      done
    fi
    for svc in "${services[@]}"; do
      echo ">> building atlas-${svc}:dev"
      docker build --build-arg "SERVICE_NAME=${svc}" -t "atlas-${svc}:dev" .
      kind load docker-image "atlas-${svc}:dev" --name "{{ KIND_CLUSTER }}"
    done
