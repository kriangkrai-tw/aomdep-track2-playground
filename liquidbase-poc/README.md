# Liquibase PoC

Demonstrates one **creation** path and three **apply** paths for Liquibase change management against SQL Server.

- **Creation** (the developer's workflow): SQL changesets live in [`compose-demo/service/src/main/resources/db/changelog/`](compose-demo/service/src/main/resources/db/changelog/), tracked in git alongside the application that owns the schema.
- **Apply mode 1 — Spring Boot embedded** ([compose-demo](compose-demo/)): the service runs migrations on startup via `liquibase-core` on its classpath. Convenient for local dev.
- **Apply mode 2 — CLI runner in a CI-shaped container** ([compose-demo](compose-demo/)): an Ubuntu container with the Liquibase CLI installed, mounting the same changelog directory. Mimics what a GitHub Actions runner step would do.
- **Apply mode 3 — Kubernetes Job** ([k8s-demo](k8s-demo/)): a thin migration image baked from the same changelog, run as a one-shot Job in a kind cluster.

## Layout

```
liquibase-poc/
├── compose-demo/                  # MSSQL + Spring service + Ubuntu runner, all in Docker
│   ├── docker-compose.yml
│   ├── service/                   # creation side AND apply mode 1
│   └── runner/                    # apply mode 2
├── k8s-demo/                      # apply mode 3, fully self-contained
│   ├── kind-config.yaml
│   ├── manifests/
│   └── migrate-image/
└── examples/github-actions/       # reference YAML, not run as part of the demo
```

## Prerequisites

- Docker Desktop (or Docker Engine + compose v2)
- For [k8s-demo](k8s-demo/): `kind` ≥ 0.20 and `kubectl`
- JDK and Maven are NOT required on the host — the service is built inside its container.

### Apple Silicon — required setup

Microsoft only ships SQL Server as `linux/amd64`. Their arm64 alternative (Azure SQL Edge) is deprecated and crashes during master-DB upgrade on recent Apple Silicon hosts. So this PoC uses real `mssql/server:2022` under **Rosetta** emulation — much faster than QEMU.

**Before running anything:**

1. Docker Desktop → Settings → General → enable **"Use Rosetta for x86_64/amd64 emulation on Apple Silicon"**.
2. Settings → Resources → bump Memory to **6 GB** or higher (SQL Server needs ≥2 GB; Rosetta and Java add overhead).
3. Apply & Restart.

First boot of MSSQL takes ~60–90s under Rosetta. Subsequent boots are quicker. Without Rosetta you'll see the same hang you hit before.

`platform: linux/amd64` is set explicitly in [compose-demo/docker-compose.yml](compose-demo/docker-compose.yml) and [k8s-demo/manifests/mssql.yaml](k8s-demo/manifests/mssql.yaml) so Docker doesn't pick QEMU even if Rosetta is misconfigured — it'll fail loudly instead.

## Quickstart

```bash
# Apply modes 1 + 2 (compose)
cd compose-demo
cat README.md            # if present, otherwise see below

# Apply mode 3 (k8s)
cd ../k8s-demo
cat README.md
```

The two demos are independent — different DBs, different lifecycles. Run them separately.

## Single source of truth

All three apply paths consume the exact same files under `compose-demo/service/src/main/resources/db/changelog/`:

- Mode 1 reads them from the classpath at Spring Boot startup.
- Mode 2 mounts the directory into the runner container at `/workspace/changelog/`.
- Mode 3 copies the directory into the migration image at `docker build` time.

If you add a `0003-*.sql`, all three pick it up after a rebuild (mode 1, mode 3) or immediately (mode 2).
