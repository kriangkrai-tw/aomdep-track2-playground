# compose-demo

Apply modes 1 and 2 in a single `docker compose` stack. MSSQL, the Spring service, and the Ubuntu Liquibase runner share one Docker network — no host networking, no `host.docker.internal`.

## Bring up the database

```bash
docker compose up -d
```

This starts MSSQL, Adminer (http://localhost:8080), and a one-shot `db-init` container that creates the `service` database. Wait ~30s on first boot for MSSQL to come up.

## Mode 1 — Spring Boot embedded apply

```bash
docker compose --profile spring up --build service
```

The service builds, starts, and Liquibase runs migrations on the way up via `liquibase-core` on the classpath. Verify:

```bash
curl http://localhost:8081/changelog   # rows from DATABASECHANGELOG
curl http://localhost:8081/users       # empty list, but the table exists
curl http://localhost:8081/health
```

`Ctrl+C` to stop the service. The DB stays up between runs (MSSQL is in a named volume).

## Mode 2 — CLI runner (CI-shaped Ubuntu container)

```bash
docker compose --profile runner build runner
docker compose --profile runner run --rm runner update           # apply
docker compose --profile runner run --rm runner status --verbose # see pending changes
docker compose --profile runner run --rm runner tag v0.1.0       # mark a point
docker compose --profile runner run --rm runner rollback v0.1.0  # roll back to it
docker compose --profile runner run --rm runner drop-all         # nuke schema
```

The runner mounts [`service/src/main/resources/db/changelog/`](service/src/main/resources/db/changelog/) read-only at `/workspace/changelog/` — same files mode 1 reads from the classpath.

## Reset

```bash
docker compose down -v   # also drops the mssql-data volume
```

## Try a new changeset

1. Add `service/src/main/resources/db/changelog/changesets/0003-something.sql`.
2. Add an `<include>` line to `db.changelog-master.xml`.
3. For mode 1: `docker compose --profile spring up --build service` (rebuild bakes the new file in).
4. For mode 2: `docker compose --profile runner run --rm runner update` (no rebuild — the runner reads the changelog from the mounted volume).

The mode-1-vs-mode-2 difference here is real: the Spring service ships with its changelog baked into the jar, so you redeploy the service to ship migrations. The runner reads them off disk, so it picks up edits immediately. The Kubernetes Job ([k8s-demo/](../k8s-demo/)) behaves like mode 1 — changelog baked into the image at build time.
