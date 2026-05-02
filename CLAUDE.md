# CLAUDE.md

Conventions and context for this repo. See `PLAN.md` for the full design.

## What this repo is

A monorepo for [Atlas](https://atlasgo.io/)-managed Postgres migrations across
multiple databases, deployed to a local [kind](https://kind.sigs.k8s.io/)
cluster via ArgoCD. Each database is a directory under `db/`. A single
ApplicationSet discovers databases by scanning `db/*` and templates one
ArgoCD Application per database. Each Application owns both the per-db
Postgres and the migrate Job; sync waves order them (postgres first, Job
second).

## Layout conventions

- `db/<name>/migrations/` — Atlas migrations + `atlas.sum`.
- `db/<name>/k8s/resources/` — raw manifests (Job, ServiceAccount, postgres
  StatefulSet/Service/PVC). No `kustomization.yaml` here; the overlay
  enumerates the files directly.
- `db/<name>/k8s/overlays/production/kustomization.yaml` — lists resources,
  generates the atlas ConfigMap (`DATABASE_URL`, `ATLAS_ENV`), applies
  per-db patches.

Overlays cross kustomization roots in two places: per-db overlays reference
`../../resources/<file>.yaml`, and `k8s/cluster/production/kustomization.yaml`
references `../../apps/...`. Both need `--load-restrictor LoadRestrictionsNone`.
This is set globally for ArgoCD via `kustomize.buildOptions` in the
`argocd-cm` ConfigMap (patched by `k8s/apps/argocd/overlays/production/kustomization.yaml`);
local `kustomize build` invocations need to pass the flag explicitly.
- `k8s/cluster/production/app.yaml` — App-of-Apps root (applied by `just up`).
- `k8s/cluster/production/kustomization.yaml` — what the root App syncs;
  pulls in the argocd install and the database-sets ApplicationSet.
- `k8s/apps/argocd/` — self-managed ArgoCD install (also used for the manual
  bootstrap).
- `k8s/apps/database-sets/appset.yaml` — the single ApplicationSet over `db/*`.

File naming: ArgoCD `Application` manifests are `app.yaml`; ArgoCD
`ApplicationSet` manifests are `appset.yaml`.
- `atlas.hcl` and `Dockerfile` are shared at the repo root.

## Adding a new database

`just new <name>` scaffolds `db/<name>/{migrations,k8s/{resources,overlays/production}}`.
The ApplicationSet picks it up automatically — no edits outside the new
directory.

## Justfile is the entry point

All cluster, build, and migration workflows go through `just`. Targets are
idempotent. See `PLAN.md` for the target table. Cluster lifecycle is `just up`
and `just down`.

## Local-only assumptions

- Single kind cluster named `atlas-local`.
- Per-db images are built locally and loaded into the cluster via
  `kind load docker-image`. No registry.
- Only a `production` overlay exists. Add others later if needed.
- Postgres credentials are hardcoded in the production overlays; revisit if
  this ever leaves the playground.

## Style

- No comments in code unless a non-obvious *why* is needed.
- Don't add backwards-compatibility shims — this is a greenfield repo.
- Don't introduce abstractions beyond what's needed for the dbs that exist.
- Alphabetize multi-line lists where order doesn't affect behavior — kustomization
  `resources:`, `patches:`, generator literals, etc.
