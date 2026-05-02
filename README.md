# atlas-monorepo

A monorepo for Postgres migrations across multiple databases, deployed to a
local [kind](https://kind.sigs.k8s.io/) cluster via ArgoCD.

Each database lives under `db/`. An ApplicationSet scans `db/*` and templates
one ArgoCD Application per database, owning both the per-db Postgres
(CloudNative-PG) and the migrate Job. Sync waves run Postgres first, the
migrate Job second.

## Prerequisites

- [atlas](https://atlasgo.io/) (for migration authoring)
- [just](https://github.com/casey/just)
- [kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [pre-commit](https://pre-commit.com/) — run `pre-commit install` once after cloning

## Quickstart

```sh
just up        # create kind cluster, install ArgoCD, build images, apply root app
just argocd-ui # port-forward ArgoCD on https://localhost:8080
just down      # tear down the kind cluster
```

Run `just` with no args for the full recipe list.

## Migrations

```sh
just n <svc> <name>  # create a new migration file (alias for `new`)
```

After editing a migration's SQL, run `atlas migrate hash --dir file://db/<svc>/migrations`
to refresh `atlas.sum`. The `atlas-migrate-validate` pre-commit hook blocks commits
with a stale sum.

## Layout

- `db/` — one directory per database (Atlas migrations + per-db k8s manifests).
- `python/` — uv-managed Python services whose images back migrate Jobs.
- `k8s/` — ArgoCD, CloudNative-PG, and ApplicationSets that wire everything together.
