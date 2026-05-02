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

## Quickstart

```sh
just up        # create kind cluster, install ArgoCD, build images, apply root app
just argocd-ui # port-forward ArgoCD on https://localhost:8080
just down      # tear down the kind cluster
```

Run `just` with no args for the full recipe list.

## Migrations

```sh
just migrate-new  <svc> <name>  # create a new migration file
just migrate-hash <svc>         # recompute atlas.sum after manual edits
just migrate-lint <svc>         # lint against an ephemeral postgres dev container
```

## Layout

- `db/` — one directory per database (Atlas migrations + per-db k8s manifests).
- `python/` — uv-managed Python services whose images back migrate Jobs.
- `k8s/` — ArgoCD, CloudNative-PG, and ApplicationSets that wire everything together.
