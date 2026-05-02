set quiet

KIND_CLUSTER := "atlas-local"

alias au := argocd-ui
alias b := build
alias d := down
alias n := new
alias u := up

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
    kustomize build k8s/apps/argocd/overlays/production | kubectl apply --server-side --force-conflicts -f -
    kubectl wait --for=condition=available --timeout=300s deploy/argocd-server -n argocd
    just build
    kubectl apply -f k8s/apps/applications/app.yaml
    kubectl config set-context --current --namespace=argocd

[doc('Delete the kind cluster.')]
[group('cluster')]
[confirm('Delete kind cluster atlas-local?')]
down:
    kind delete cluster --name "{{ KIND_CLUSTER }}"

[doc('Print the ArgoCD initial admin password.')]
[group('cluster')]
argocd-password:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode
    echo

[doc('Print the admin URL + password, then port-forward argocd-server.')]
[group('cluster')]
argocd-ui:
    #!/usr/bin/env bash
    set -euo pipefail
    password=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)
    echo "admin password is ${password}"
    echo "https://localhost:8080"
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
    atlas migrate new --dir file://db/{{ SVC }}/migrations {{ NAME }}

[doc('Recompute atlas.sum for db/<SVC>/migrations.')]
[group('migrate')]
migrate-hash SVC:
    atlas migrate hash --dir file://db/{{ SVC }}/migrations

[doc('Lint migrations against an ephemeral postgres dev container.')]
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
