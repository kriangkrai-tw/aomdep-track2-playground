# k8s-demo

Apply mode 3: a Kubernetes Job applies migrations against an in-cluster MSSQL.

Self-contained. Doesn't share state with [compose-demo](../compose-demo/) — different MSSQL, different cluster.

## Prerequisites

- Docker
- `kind` ≥ 0.20
- `kubectl`

## Walkthrough

```bash
# 1. Build the migration image. Build context is the REPO ROOT so the COPY
#    statement can reach the shared changelog under compose-demo/service/...
cd ..
docker build -f k8s-demo/migrate-image/Dockerfile -t poc-migrate:0.1.0 .
cd k8s-demo

# 2. Create the cluster.
kind create cluster --config kind-config.yaml

# 3. Load the migration image into the kind node so it doesn't need a registry.
kind load docker-image poc-migrate:0.1.0 --name liquibase-poc

# 4. Apply the static manifests.
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/secret-db.yaml
kubectl apply -f manifests/mssql.yaml
kubectl -n liquibase-poc rollout status deploy/mssql

# 5. Run the migration Job.
kubectl apply -f manifests/job.yaml
kubectl -n liquibase-poc wait --for=condition=Complete job/liquibase-update --timeout=300s

# 6. See what it did.
kubectl -n liquibase-poc logs job/liquibase-update

# Inspect the DB. Azure SQL Edge ships without sqlcmd, so port-forward and use
# any client (Adminer, Azure Data Studio, DBeaver):
kubectl -n liquibase-poc port-forward svc/mssql 1433:1433
# Then connect to localhost:1433 as sa / Liquib@se-PoC-2026.
```

## Image / arch note

Engine is `mcr.microsoft.com/azure-sql-edge:latest` — native arm64, runs unemulated on Apple Silicon kind nodes. The init container reuses the `poc-migrate` image (Liquibase + MSSQL JDBC) and runs `liquibase execute-sql` to create the `service` database; this avoids pulling an amd64 sqlcmd image into the kind node.

## Re-run

The Job's name is fixed (`liquibase-update`), so re-running needs a delete:

```bash
kubectl -n liquibase-poc delete job liquibase-update
kubectl apply -f manifests/job.yaml
```

A re-applied Job will be a no-op against an already-migrated DB — Liquibase skips the changesets recorded in `DATABASECHANGELOG`.

## Try a new changeset

1. Add a `0003-*.sql` under [`compose-demo/service/src/main/resources/db/changelog/changesets/`](../compose-demo/service/src/main/resources/db/changelog/changesets/) and add an `<include>` in the master.
2. Rebuild the image: `docker build -f k8s-demo/migrate-image/Dockerfile -t poc-migrate:0.2.0 .` (from repo root).
3. Reload into kind: `kind load docker-image poc-migrate:0.2.0 --name liquibase-poc`.
4. Edit `manifests/job.yaml` to point at `:0.2.0`, delete + re-apply the Job.

## Teardown

```bash
kind delete cluster --name liquibase-poc
```
