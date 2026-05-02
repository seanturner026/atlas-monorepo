# Atlas Monorepo Plan

A monorepo for managing schema migrations across multiple Postgres databases
using [Atlas](https://atlasgo.io/), deployed via ArgoCD onto a local
[kind](https://kind.sigs.k8s.io/) cluster.

## Goals

- One repo, many databases. Each database is a directory under `db/`.
- Adding a new database means adding a directory — no top-level edits.
- All deploys driven by ArgoCD ApplicationSets that discover databases by
  scanning `db/*`.
- Local-only playground: kind cluster, locally-built images loaded into the
  cluster (no registry).
- A `justfile` is the single entry point for cluster, build, and migration
  workflows.

## Repo layout

```
atlas.hcl                          # shared, env-driven (ATLAS_ENV, DATABASE_URL)
Dockerfile                         # shared, ARG SERVICE_NAME selects per-db migrations
justfile
PLAN.md
CLAUDE.md
README.md

db/
  db1/
    migrations/
      20250115093000_init.sql
      atlas.sum
    k8s/
      atlas/
        resources/
          kustomization.yaml
          job.yaml                 # atlas migrate apply Job
          serviceaccount.yaml
        overlays/
          production/
            kustomization.yaml     # creates ConfigMap (DATABASE_URL, ATLAS_ENV), patches SA if needed
      postgres/
        resources/
          kustomization.yaml
          statefulset.yaml
          service.yaml
          pvc.yaml
        overlays/
          production/
            kustomization.yaml
  some-other-db/                   # mirrors db1/ — proves the AppSets pick up new dbs

k8s/
  argocd/                          # bootstrap-only: ArgoCD install
    resources/
      kustomization.yaml           # references upstream ArgoCD manifests at a pinned tag
    overlays/
      production/
        kustomization.yaml
  cluster/
    production/
      root-app.yaml                # App-of-Apps → syncs k8s/apps/
  apps/
    kustomization.yaml
    atlas-appset.yaml              # ApplicationSet over db/* → one App per db (atlas migrations)
    postgres-appset.yaml           # ApplicationSet over db/* → one App per db (postgres)
```

## ArgoCD topology

```
root-app (k8s/cluster/production/root-app.yaml)
  └── k8s/apps/   (kustomization includes both AppSets)
        ├── atlas-appset       → templates Application "atlas-<db>"   pointing at db/<db>/k8s/atlas/overlays/production
        └── postgres-appset    → templates Application "postgres-<db>" pointing at db/<db>/k8s/postgres/overlays/production
```

Both AppSets use a `git: directories` generator over `db/*`. The template uses
`{{path.basename}}` for the database name. Adding `db/foo/` with the expected
subtree produces two new ArgoCD Applications automatically.

## atlas.hcl

Single `env` block, env-var driven, so the same config works locally and in
the migrate Job:

```hcl
env "default" {
  src = "file://migrations"
  url = getenv("DATABASE_URL")
  dev = "docker://postgres/16/dev"
}
```

## Dockerfile

Per-db image. `ARG SERVICE_NAME` selects which migrations get baked in:

```dockerfile
FROM arigaio/atlas:latest
ARG SERVICE_NAME
COPY atlas.hcl /atlas.hcl
COPY db/${SERVICE_NAME}/migrations /migrations
WORKDIR /
ENTRYPOINT ["/atlas"]
CMD ["migrate", "apply", "--config", "file:///atlas.hcl", "--env", "default"]
```

Image tag convention: `atlas-<db>:dev`. Locally loaded into kind via
`kind load docker-image`.

## Justfile targets

| Target              | Behavior                                                                 |
|---------------------|--------------------------------------------------------------------------|
| `init`              | Idempotent: create kind cluster if missing, install ArgoCD, apply root App |
| `cluster-up`        | Just the kind + ArgoCD install half of `init`                            |
| `cluster-down`      | `kind delete cluster --name atlas-local`                                 |
| `argocd-password`   | Print the initial admin password                                         |
| `argocd-ui`         | Calls `argocd-password`, then port-forwards `argocd-server` on 8080      |
| `new-db NAME`       | Scaffold `db/<NAME>/{migrations,k8s/atlas,k8s/postgres}` from templates  |
| `migrate-new SVC NAME` | `atlas migrate new --dir file://db/$SVC/migrations $NAME`             |
| `migrate-hash SVC`  | Refresh `atlas.sum`                                                      |
| `migrate-lint SVC`  | `atlas migrate lint --dev-url docker://postgres/16/dev`                  |
| `build [SVC]`       | Build + `kind load` for one db, or all dbs if no arg                     |

## Improvements over the reference deploy.sh

The reference is
[`seanturner026/argocd-applicationset/deploy.sh`](https://github.com/seanturner026/argocd-applicationset/blob/main/deploy.sh).
Specific changes:

- **Idempotent.** `kind get clusters | grep` before create. `kubectl apply` is
  already idempotent for namespaces and manifests.
- **`kubectl wait` instead of polling for the secret.** Wait on
  `deploy/argocd-server` `condition=available`, single timeout, no bash loop.
- **Pinned ArgoCD version.** Kustomize references upstream manifests at a
  specific tag, not `stable`.
- **App-of-apps.** A single `kubectl apply` of the root App brings up postgres
  + atlas; the script doesn't need to know about either.
- **Port-forward separated.** `init` exits cleanly. `argocd-ui` is the
  interactive target.
- **`kind load docker-image` baked into `build`.** Locally-built per-db images
  are visible to the cluster without a registry.

## Implementation order

1. Skeleton: `atlas.hcl`, `Dockerfile`, `justfile`, `.gitignore`, one
   `db/db1/migrations/` with a trivial init migration + `atlas.sum`.
2. Per-db k8s for `db1` (`atlas/` and `postgres/` resources + `production`
   overlay).
3. `k8s/argocd/` bootstrap kustomize, plus `cluster-up` / `init` justfile
   targets. Verify ArgoCD comes up cleanly.
4. App-of-apps (`k8s/cluster/production/root-app.yaml`, `k8s/apps/*`).
5. Both ApplicationSets, with `db1` as the only target.
6. `just new-db some-other-db` to confirm a fresh dir produces two new
   ArgoCD Applications with no top-level edits.

## Open questions

- ArgoCD version to pin to.
- Postgres image/version (default to `postgres:16`).
- Migration credential strategy: hardcoded local creds in the production
  overlay for now; revisit if/when this leaves the playground.
