# Dynatrace POC on Minikube — Todo Service

Observability POC using **Dynatrace Operator** (`cloudNativeFullStack`) to monitor a Spring Boot Java service running in local Minikube. Covers distributed tracing, JVM metrics, and log ingestion — no third-party log shippers required.

---

## Architecture

```
Minikube cluster (Docker driver, 4 CPU, 8 GB RAM)
├── namespace: dynatrace
│   ├── Dynatrace Operator (Helm, OCI registry)
│   ├── DynaKube CR — cloudNativeFullStack
│   │   ├── OneAgent DaemonSet (auto-injected into pods)
│   │   │   └── Log module — collects container stdout/stderr
│   │   └── ActiveGate StatefulSet
│   │       └── Capabilities: routing, kubernetes-monitoring
└── namespace: todo-app
    ├── todo-service  (Spring Boot 3, Java 17, JSON logging)
    │   ├── GET /hello  → 200 — generates traces + info logs
    │   ├── GET /error  → 500 — generates error traces + error logs
    │   └── GET /api/todos, POST /api/todos, …  (CRUD)
    └── postgres        (backend database)
```

---

## Prerequisites

| Tool | Notes |
|------|-------|
| **Docker Desktop** | On Apple Silicon: enable **Settings → General → "Use Rosetta for x86/amd64 emulation"** |
| **Minikube** ≥ 1.32 | `brew install minikube` |
| **Helm** ≥ 3.14 | `brew install helm` |
| **kubectl** | `brew install kubectl` |
| **envsubst** | Ships with GNU gettext — `brew install gettext && brew link gettext --force` |
| **Dynatrace SaaS account** | Free trial: https://www.dynatrace.com/trial/ |

---

## Dynatrace Token Setup

1. Log in to your Dynatrace environment.
2. Go to **Access tokens** → **Generate new token** (https://`<your-env-id>`.apps.dynatrace.com/ui/access-tokens).
3. Give the token a name (e.g. `minikube-poc`).
4. Enable the following scopes:
   - `Write API tokens`
   - `Access problem and event feed, metrics, and topology`
   - `Read entities`
   - `Write entities`
   - `PaaS integration — Installer download`
   - `Ingest logs` (`logs.ingest`)
5. Click **Generate token** and copy the value — it won't be shown again.
6. The same token can be used for both `DT_API_TOKEN` and `DT_DATA_INGEST_TOKEN`.

---

## Quick Start

```bash
# 1. Export credentials
export DT_ENV_ID=abc12345                    # your env ID (subdomain only)
export DT_API_TOKEN=dt0c01.XXXX...           # from the step above
export DT_DATA_INGEST_TOKEN="${DT_API_TOKEN}" # can reuse the same token

# 2. Run setup (idempotent — safe to re-run)
./setup.sh

# 3. Verify observability data
./verify.sh

# 4. Open Dynatrace
open "https://${DT_ENV_ID}.apps.dynatrace.com/ui/apps/dynatrace.classic.kubernetes/"
```

> **Tip:** `setup.sh` is fully idempotent. If it fails mid-way, re-run it — already-completed steps are skipped.

---

## What You'll See in Dynatrace

### Kubernetes view
**Kubernetes → Clusters → minikube** — node CPU/memory, pod restarts, workload health.

### Services (auto-detected)
Dynatrace auto-discovers `todo-service` as a Java service.  
**Applications & Microservices → Services** → search for `todo-service`.

### Distributed Traces
**Applications & Microservices → Distributed traces** — each HTTP request to `/hello`, `/error`, or `/api/todos` generates a trace.

### JVM Metrics
**Infrastructure → Technologies → JVM** — heap usage, GC pause times, thread counts, class loading.

### Container Logs
**Logs** → filter `k8s.namespace.name = "todo-app"` — JSON-structured logs enriched with pod name, container name, namespace, and correlated to traces via `trace_id`.

---

## Manual Step in Dynatrace UI

After setup, verify the log collection feature flag is enabled:

1. **Settings → Log Monitoring → Log module feature flags**
2. Enable **"Collect all container logs"** (enabled by default on new tenants).

This ensures stdout logs from all containers are captured.

---

## Generating Test Traffic

```bash
# In one terminal: start port-forward
kubectl port-forward svc/todo-service -n todo-app 8080:80

# In another terminal: send traffic
curl http://localhost:8080/hello        # → 200 {"message":"Hello from todo-service!"}
curl http://localhost:8080/error        # → 500 (intentional error for observability)
curl http://localhost:8080/api/todos    # → 200 [] (CRUD endpoint)
```

---

## Known Limitations

- **Free trial log ingest limit**: ~50 MB/day — more than enough for this POC.
- **First data delay**: Traces and logs typically appear 3–5 minutes after OneAgent starts.
- **Apple Silicon image pulls**: Initial pulls of amd64 layers take longer due to Rosetta emulation.
- **ActiveGate startup**: On first install ActiveGate takes 2–4 minutes to register with the Dynatrace cloud.

---

## Teardown

```bash
# Remove all Kubernetes resources (keeps Minikube running)
./teardown.sh

# Remove resources AND stop Minikube
./teardown.sh --stop-minikube
```

---

## Troubleshooting

### Token scope errors (`401 Unauthorized` or `403 Forbidden`)
Verify the API token has all required scopes listed in [Dynatrace Token Setup](#dynatrace-token-setup).  
Re-create the secret: `kubectl delete secret dynakube -n dynatrace && ./setup.sh`

### Pods stuck in `Pending`
Minikube may need more resources:
```bash
minikube stop
minikube start --cpus=4 --memory=8192 --driver=docker
```

### DNS resolution failures inside Minikube
```bash
minikube ssh -- nslookup abc12345.live.dynatrace.com
```
If this fails, check that the Docker Desktop network is functioning and your `DT_ENV_ID` is correct.

### OneAgent not injected (no `install-oneagent` init container)
```bash
# Verify namespace label is present
kubectl get ns todo-app --show-labels

# Re-apply the label and restart
kubectl label ns todo-app dynatrace.com/inject=true --overwrite
kubectl rollout restart deployment/todo-service -n todo-app
```

### ActiveGate stuck in `Pending` (Apple Silicon)
The operator sets an `amd64`-only node affinity but Minikube on Apple Silicon is `arm64`. `setup.sh` patches this automatically. To fix manually:
```bash
kubectl patch statefulset dynakube-activegate -n dynatrace --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/0/values","value":["amd64","arm64"]},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":180},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":4},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":10},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":180},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":6},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":10}
]'
kubectl delete pod -n dynatrace -l app.kubernetes.io/component=activegate --ignore-not-found
```
> **Why three settings?** Rosetta 2 emulates x86-64 ActiveGate on ARM64: `initialDelaySeconds=180` gives it time to start, `failureThreshold` adds retries, and `timeoutSeconds=10` lets the TLS handshake complete (default 1 s is too tight under emulation).

### ActiveGate CrashLoopBackOff
Usually a token/permission issue. Check logs:
```bash
kubectl logs -n dynatrace -l app.kubernetes.io/component=activegate --tail=50
```

### `envsubst` not found on macOS
```bash
brew install gettext
brew link gettext --force
```

---

## Key References

- [Dynatrace Operator deployment](https://docs.dynatrace.com/docs/ingest-from/setup-on-k8s/deployment)
- [cloudNativeFullStack setup](https://docs.dynatrace.com/docs/ingest-from/setup-on-k8s/deployment/full-stack-observability)
- [Kubernetes log monitoring](https://docs.dynatrace.com/docs/ingest-from/setup-on-k8s/deployment/k8s-log-monitoring)
- [Log module feature flags](https://docs.dynatrace.com/docs/analyze-explore-automate/logs/lma-log-ingestion/lma-log-ingestion-via-oa/lma-feature-flags)
- [DynaKube parameters reference](https://docs.dynatrace.com/docs/ingest-from/setup-on-k8s/reference/dynakube-parameters)
- [Multi-arch container images](https://docs.dynatrace.com/docs/ingest-from/setup-on-k8s/guides/container-registries/use-public-registry)
