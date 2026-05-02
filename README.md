# atlas-monorepo

A monorepo for Postgres migrations across multiple databases, deployed to a
local [kind](https://kind.sigs.k8s.io/) cluster via ArgoCD.

Each database lives under `db/`. An ApplicationSet scans `db/*` and templates
one ArgoCD Application per database, owning both the per-db Postgres
(CloudNative-PG) and the migrate Job. Sync waves run Postgres first, the
migrate Job second.

The delivery pipeline is uniform; the migration authoring tool is per-db:

- **Atlas** (`db/<name>/migrations/` present) — hand-written SQL files plus
  `atlas.sum`. Image is built from the top-level `Dockerfile` as
  `atlas-<name>:dev`. Job runs `atlas migrate apply`.
- **Alembic** (no `migrations/` in the db dir) — migrations live alongside a
  Python service under `python/<service>/alembic/`. Image is built from
  `python/<service>/Dockerfile`. Job runs `alembic upgrade head`. Integrity
  comes from Alembic's revision chain rather than `atlas.sum`.

Either way, the Job consumes `DATABASE_URL` from the CNPG-managed
`<name>-app` Secret — the ApplicationSet doesn't care which runner ran.

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
just n <svc> <name>  # create a new migration file (alias for `new`)
just h <svc>         # recompute atlas.sum after editing (alias for `hash`)
```

Both recipes target Atlas-managed dbs. Alembic dbs are authored inside the
relevant `python/<service>/` package using `alembic revision`.

## Layout

- `db/` — one directory per database. Atlas dbs keep `migrations/` here;
  Alembic dbs only ship k8s manifests and defer to a `python/` service.
- `python/` — uv-managed Python services. Each Dockerfile produces the image
  used by an Alembic-style migrate Job (e.g. `python/api` → `api:dev`,
  consumed by `db/db-alembic`).
- `k8s/` — ArgoCD, CloudNative-PG, and ApplicationSets that wire everything together.
