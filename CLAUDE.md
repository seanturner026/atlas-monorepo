# CLAUDE.md

Conventions and context for this repo. See `PLAN.md` for the full design.

## What this repo is

A monorepo for [Atlas](https://atlasgo.io/)-managed Postgres migrations across
multiple databases, deployed to a local [kind](https://kind.sigs.k8s.io/)
cluster via ArgoCD. Each database is a directory under `db/`. Two
ApplicationSets discover databases by scanning `db/*` and template one
ArgoCD Application per database for migrations and one for the postgres
StatefulSet.

## Layout conventions

- `db/<name>/migrations/` — Atlas migrations + `atlas.sum`.
- `db/<name>/k8s/atlas/{resources,overlays/production}` — migrate Job +
  ServiceAccount, plus an overlay that creates the ConfigMap with
  `DATABASE_URL` / `ATLAS_ENV` and patches the SA if needed.
- `db/<name>/k8s/postgres/{resources,overlays/production}` — StatefulSet,
  Service, PVC for the per-db Postgres.
- `k8s/argocd/` — ArgoCD install (bootstrap only).
- `k8s/cluster/production/root-app.yaml` — App-of-Apps root.
- `k8s/apps/` — child Apps; both ApplicationSets live here.
- `atlas.hcl` and `Dockerfile` are shared at the repo root.

## Adding a new database

`just new-db <name>` scaffolds `db/<name>/{migrations,k8s/atlas,k8s/postgres}`.
The two ApplicationSets pick it up automatically — no edits outside the new
directory.

## Justfile is the entry point

All cluster, build, and migration workflows go through `just`. Targets are
idempotent. See `PLAN.md` for the target table.

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
