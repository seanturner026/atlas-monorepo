# Atlas Monorepo Plan

A monorepo for managing schema migrations across multiple Postgres databases
using [Atlas](https://atlasgo.io/), deployed via ArgoCD onto a local
[kind](https://kind.sigs.k8s.io/) cluster.

## Goals

- One repo, many databases. Each database is a directory under `db/`.
- Adding a new database means adding a directory — no top-level edits.
- A single ArgoCD ApplicationSet discovers databases by scanning `db/*` and
  templates one Application per database. Each Application owns both the
  per-db Postgres and the migrate Job (sync waves order them).
- Local-only playground: kind cluster, locally-built images loaded into the
  cluster (no registry).
- A `justfile` is the single entry point for cluster, build, and migration
  workflows.

## Repo layout

```
atlas.hcl                          shared, env-driven (ATLAS_ENV, DATABASE_URL)
Dockerfile                         multi-stage: atlas binary copied into scratch (or distroless/static)
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
      resources/                   raw manifests, no kustomization.yaml here
        job.yaml                   atlas migrate apply Job        (sync-wave "1")
        serviceaccount.yaml
        statefulset.yaml           postgres StatefulSet           (sync-wave "0")
        service.yaml               postgres Service
        pvc.yaml                   postgres PVC
      overlays/
        production/
          kustomization.yaml       enumerates the resource files, generates the
                                   atlas ConfigMap (DATABASE_URL, ATLAS_ENV),
                                   applies any per-db patches
  some-other-db/                   mirrors db1/ — proves the AppSet picks up new dbs

k8s/
  cluster/
    production/
      app.yaml                     App-of-Apps → syncs k8s/cluster/production
      kustomization.yaml           includes argocd/ and database-sets/
  apps/
    argocd/                        self-managed ArgoCD install (also used for the manual bootstrap)
      resources/
        kustomization.yaml         references upstream ArgoCD manifests at a pinned tag
      overlays/
        production/
          kustomization.yaml
    postgres/                      (planned) CloudNative-PG operator install, same resources/+overlays/ shape
      resources/
        kustomization.yaml
      overlays/
        production/
          kustomization.yaml
    database-sets/                 single ApplicationSet over db/*
      appset.yaml
```

## ArgoCD topology

```
root-app  (k8s/cluster/production/app.yaml)
└── k8s/cluster/production/                kustomization.yaml pulls in both children from k8s/apps/
    ├── argocd/                            self-management of the ArgoCD install (k8s/apps/argocd/)
    └── database-sets/                     ApplicationSet (k8s/apps/database-sets/), generator: git directories over db/*
        ├── App "db1"             →  db/db1/k8s/overlays/production
        │   ├── postgres StatefulSet / Service / PVC      (sync-wave "0")
        │   └── atlas migrate Job + SA + ConfigMap         (sync-wave "1")
        └── App "some-other-db"   →  db/some-other-db/k8s/overlays/production
            ├── postgres …
            └── atlas …
```

ArgoCD is installed manually once (`just up`) from `k8s/apps/argocd/` and then
managed by the same path via the root App, so future ArgoCD upgrades are
GitOps-driven.

## atlas.hcl

Single `env`, env-var driven:

```hcl
env "default" {
  src = "file://migrations"
  url = getenv("DATABASE_URL")
  dev = "docker://postgres/16/dev"
}
```

## Dockerfile

Multi-stage: pull the `atlas` binary out of the upstream image and put it in a
minimal final layer. Scratch works because the binary is statically linked;
`distroless/static` is the safer choice if anything ends up needing CA
certificates.

```dockerfile
FROM arigaio/atlas:latest AS atlas

FROM gcr.io/distroless/static:nonroot
ARG SERVICE_NAME
COPY --from=atlas /atlas /atlas
COPY atlas.hcl /atlas.hcl
COPY db/${SERVICE_NAME}/migrations /migrations
ENTRYPOINT ["/atlas"]
CMD ["migrate", "apply", "--config", "file:///atlas.hcl", "--env", "default"]
```

Image tag convention: `atlas-<db>:dev`. Loaded into kind via
`kind load docker-image`.

Decision to confirm: scratch vs `distroless/static:nonroot`. Default to
distroless until something forces it smaller.

## Justfile targets

| Target              | Behavior                                                                 |
|---------------------|--------------------------------------------------------------------------|
| `up`                | Idempotent: create kind cluster if missing, install ArgoCD, apply root App |
| `down`              | `kind delete cluster --name atlas-local`                                 |
| `argocd-password`   | Print the initial admin password                                         |
| `argocd-ui`         | Calls `argocd-password`, then port-forwards `argocd-server` on 8080      |
| `new NAME`          | Scaffold `db/<NAME>/{migrations,k8s/{resources,overlays/production}}`    |
| `migrate-new SVC NAME` | `atlas migrate new --dir file://db/$SVC/migrations $NAME`             |
| `migrate-hash SVC`  | Refresh `atlas.sum`                                                      |
| `migrate-lint SVC`  | `atlas migrate lint --dev-url docker://postgres/16/dev`                  |
| `build [SVC]`       | Build + `kind load` for one db, or all dbs if no arg                     |

## Improvements over the reference deploy.sh

The reference is
[`seanturner026/argocd-applicationset/deploy.sh`](https://github.com/seanturner026/argocd-applicationset/blob/main/deploy.sh).
Specific changes:

- **Idempotent.** `kind get clusters | grep` before create; `kubectl apply` is
  already idempotent for namespaces and manifests.
- **`kubectl wait` instead of polling for the secret.** Wait on
  `deploy/argocd-server` `condition=available`, single timeout, no bash loop.
- **Pinned ArgoCD version.** Kustomize references upstream manifests at a
  specific tag, not `stable`.
- **App-of-apps + self-managing ArgoCD.** A single root manifest brings up
  everything; future ArgoCD upgrades are GitOps changes, not script edits.
- **Port-forward separated.** `up` exits cleanly; `argocd-ui` is the
  interactive target.
- **`kind load docker-image` baked into `build`.** Locally-built per-db
  images are visible to the cluster without a registry.

## Implementation order

- [x] Skeleton: `atlas.hcl`, `Dockerfile`, `justfile`, `.gitignore`, one
  `db/db1/migrations/` with a trivial init migration + `atlas.sum`.
- [x] Per-db k8s for `db1` (resources/ + overlays/production), with sync-wave
  annotations so postgres precedes the migrate Job.
- [x] `k8s/apps/argocd/` install kustomize, plus `up` / `down` justfile targets.
- [ ] Verify ArgoCD comes up cleanly via `just up` against a real kind cluster.
- [x] App-of-apps (`k8s/cluster/production/app.yaml` + `kustomization.yaml`)
  plus self-management of argocd.
- [x] The `database-sets` ApplicationSet, with `db1` as the only target.
- [ ] `just new some-other-db` to confirm a fresh dir produces a new ArgoCD
  Application with no top-level edits.
- [ ] Add the postgres operator (likely CloudNative-PG) as `k8s/apps/postgres/`
  (resources/ + overlays/production/, same shape as `argocd/`), wire it into
  `k8s/cluster/production/kustomization.yaml`, and replace the per-db
  StatefulSet/Service/PVC with a single `Cluster` CR per `db/<name>/`.

## Open questions

- ArgoCD version pin: **v3.3.9**.
- Postgres image/version: **`postgres:16`** (revisit once the operator lands).
- Final image base: **`gcr.io/distroless/static:nonroot`**.
- Migration credential strategy: hardcoded in the production overlay for now;
  revisit when adopting the postgres operator (operator-managed Secret).
