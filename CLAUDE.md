# CLAUDE.md

Conventions and context for this repo.

## What this repo is

A monorepo for Postgres migrations across multiple databases, deployed to a
local [kind](https://kind.sigs.k8s.io/) cluster via ArgoCD. Each database is
a directory under `db/`. A single ApplicationSet discovers databases by
scanning `db/*` and templates one ArgoCD Application per database. Each
Application owns both the per-db Postgres and the migrate Job; sync waves
order them (postgres first, Job second).

Migration tooling per db:

- `db/<name>/migrations/` present → [Atlas](https://atlasgo.io/), built from
  the top-level `Dockerfile` (image `atlas-<name>:dev`).
- No `migrations/` → the migrate Job pulls a separate image, typically built
  from a sibling python service under `python/<service>/`. The Job's
  `image:` field names the service; ImageUpdater would track new tags in a
  real deployment.

## Layout conventions

- `db/<name>/migrations/` — Atlas migrations + `atlas.sum` (omit for python-image dbs).
- `db/<name>/k8s/resources/` — raw manifests (CNPG `Cluster` CR, migrate Job,
  ServiceAccount). No `kustomization.yaml` here; the overlay enumerates the
  files directly.
- `db/<name>/k8s/overlays/production/kustomization.yaml` — lists resources
  and applies any per-db patches. `DATABASE_URL` for the migrate Job comes
  from the operator-managed `<name>-app` Secret (`uri` key); no ConfigMap
  generation needed.
- `python/<service>/` — uv-managed Python package whose Dockerfile produces
  the image used by one or more migrate Jobs (e.g. `python/api` produces
  `api:dev`, used by `db/db-alembic`'s Job to run `alembic upgrade head`).

Per-db overlays reference `../../resources/<file>.yaml` across kustomization
roots, which requires `--load-restrictor LoadRestrictionsNone`. This is set
globally for ArgoCD via `kustomize.buildOptions` in the `argocd-cm` ConfigMap
(patched by `k8s/apps/argocd/overlays/production/kustomization.yaml`); local
`kustomize build` invocations need to pass the flag explicitly.

- `k8s/apps/applications/app.yaml` — bootstrap Application applied by `just up`.
- `k8s/apps/applications/overlays/production/appset.yaml` — `applications`
  ApplicationSet that templates one Application per `k8s/apps/*/overlays/production`
  (excluding itself), so adding a new app is just a new directory.
- `k8s/apps/argocd/` — self-managed ArgoCD install (also used for the manual
  bootstrap).
- `k8s/apps/database-sets/overlays/production/appset.yaml` — `databases`
  ApplicationSet over `db/*`.
- `k8s/apps/postgres/` — CloudNative-PG operator install.

File naming: ArgoCD `Application` manifests are `app.yaml`; ArgoCD
`ApplicationSet` manifests are `appset.yaml`.
- `atlas.hcl` and `Dockerfile` are shared at the repo root.

## Adding a new database

`just new <name>` scaffolds `db/<name>/{migrations,k8s/{resources,overlays/production}}`.
The ApplicationSet picks it up automatically — no edits outside the new
directory.

## Justfile is the entry point

All cluster, build, and migration workflows go through `just`. Targets are
idempotent. Run `just` (no args) for the list. Cluster lifecycle is `just up`
and `just down`.

## Local-only assumptions

- Single kind cluster named `atlas-local`.
- All images (atlas + python) are built locally by `just build` and loaded
  into the cluster via `kind load docker-image`. No registry. ImageUpdater
  is the production story for python-image dbs and is out of scope here.
- Only a `production` overlay exists. Add others later if needed.
- Postgres credentials are hardcoded in the production overlays; revisit if
  this ever leaves the playground.

## Style

- No comments in code unless a non-obvious *why* is needed.
- Don't add backwards-compatibility shims — this is a greenfield repo.
- Don't introduce abstractions beyond what's needed for the dbs that exist.
- Alphabetize multi-line lists where order doesn't affect behavior — kustomization
  `resources:`, `patches:`, generator literals, etc.
- Don't prefix resource names with their namespace. Each db has its own namespace,
  so `db1/atlas` and `db1/migrate` rather than `db1/db1-atlas` and `db1/db1-migrate`.
  CNPG-generated names (`db1-app`, `db1-rw`, `db1-1`) derive from the Cluster name
  and stay as the operator emits them.
