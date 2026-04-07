#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# ============================================================
# setup.sh — Idempotent setup of Dynatrace + todo-service POC
#            on local Kubernetes via Colima
# ============================================================
#
# Required env vars (export before running):
#   DT_ENV_ID            — Dynatrace environment ID (e.g. abc12345)
#   DT_API_TOKEN         — Dynatrace API token
#   DT_DATA_INGEST_TOKEN — Data ingest token (can equal DT_API_TOKEN)
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
err()  { echo -e "${RED}❌  ERROR: $*${NC}" >&2; }
info() { echo -e "${GREEN}ℹ️   $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️   $*${NC}"; }
step() { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── 1. Validate required environment variables ───────────────
step "Validating environment variables"
MISSING=0
for var in DT_ENV_ID DT_API_TOKEN DT_DATA_INGEST_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    err "Required variable '${var}' is not set."
    echo "  export ${var}=your-value"
    MISSING=1
  fi
done
[[ "${MISSING}" -eq 0 ]] || exit 1
info "All required environment variables are set."

# ── 2. Check prerequisites ────────────────────────────────────
step "Checking prerequisites"
for cmd in kubectl helm colima docker envsubst; do
  if ! command -v "${cmd}" &>/dev/null; then
    err "'${cmd}' is not installed. See README.md for installation instructions."
    exit 1
  fi
done
info "All prerequisites found."

# ── 3. Start Colima Kubernetes cluster ────────────────────────
step "Starting Colima Kubernetes cluster"
HOST_ARCH=$(uname -m)
IS_QEMU=false

if [[ "${HOST_ARCH}" == "arm64" ]]; then
  # Apple Silicon: OneAgent requires x86_64 Linux — run a QEMU x86_64 VM.
  # Ubuntu 24.04 (glibc 2.39) requires SSE4.2/POPCNT; must be added to cpu-type.
  COLIMA_PROFILE="x86k8s"
  IS_QEMU=true
  if colima status --profile "${COLIMA_PROFILE}" 2>/dev/null | grep -q "running"; then
    info "Colima profile '${COLIMA_PROFILE}' is already running (x86_64 QEMU)."
  else
    echo "🍎 Apple Silicon detected — starting Colima x86_64 QEMU VM..."
    echo "   ⚠️  First start takes 5-10 min (VM creation + Kubernetes bootstrap)."
    colima start \
      --profile "${COLIMA_PROFILE}" \
      --arch x86_64 \
      --vm-type qemu \
      --cpu-type "qemu64,+ssse3,+sse4.1,+sse4.2,+popcnt,+cx16,+lahf_lm" \
      --cpu 4 \
      --memory 8 \
      --disk 30 \
      --runtime docker \
      --kubernetes
  fi
else
  # Intel Mac: native x86_64 — no emulation needed.
  COLIMA_PROFILE="k8s"
  if colima status --profile "${COLIMA_PROFILE}" 2>/dev/null | grep -q "running"; then
    info "Colima profile '${COLIMA_PROFILE}' is already running."
  else
    echo "🚀 Starting Colima Kubernetes cluster (4 CPU, 8 GB RAM)..."
    colima start \
      --profile "${COLIMA_PROFILE}" \
      --cpu 4 \
      --memory 8 \
      --disk 30 \
      --runtime docker \
      --kubernetes
  fi
fi

DOCKER_SOCK="${HOME}/.colima/${COLIMA_PROFILE}/docker.sock"

# Point kubectl at the Colima cluster
kubectl config use-context "colima-${COLIMA_PROFILE}"
NODE_ARCH=$(kubectl get node -o jsonpath='{.items[0].status.nodeInfo.architecture}' 2>/dev/null || echo "unknown")
info "Cluster ready. Node architecture: ${NODE_ARCH}"

if [[ "${NODE_ARCH}" == "arm64" ]]; then
  err "Cluster node is ARM64 — Dynatrace OneAgent requires x86_64."
  echo "  Fix: delete the profile and re-run:"
  echo "    colima delete --profile ${COLIMA_PROFILE} && ./setup.sh"
  exit 1
fi

# ── 4. Install Dynatrace Operator via Helm (OCI registry) ────
step "Installing Dynatrace Operator"
kubectl create namespace dynatrace --dry-run=client -o yaml | kubectl apply -f -

if helm status dynatrace-operator --namespace dynatrace &>/dev/null; then
  info "Dynatrace Operator is already installed."
else
  echo "⚙️  Installing Dynatrace Operator from OCI registry..."
  helm install dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator \
    --namespace dynatrace \
    --atomic
fi

# ── 5. Wait for Operator webhook ─────────────────────────────
step "Waiting for Dynatrace Operator webhook"
kubectl -n dynatrace wait pod \
  --for=condition=ready \
  --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook \
  --timeout=300s

# ── 6. Create dynakube token secret ──────────────────────────
step "Creating dynakube secret"
kubectl -n dynatrace create secret generic dynakube \
  --from-literal="apiToken=${DT_API_TOKEN}" \
  --from-literal="dataIngestToken=${DT_DATA_INGEST_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
info "Secret 'dynakube' applied in namespace 'dynatrace'."

# ── 7. Apply DynaKube CR ──────────────────────────────────────
step "Applying DynaKube CR"
envsubst < k8s/dynakube.yaml | kubectl apply -f -
info "DynaKube CR applied (cloudNativeFullStack + logMonitoring)."
# Give the operator webhook time to register its MutatingWebhookConfiguration
# before we create deployment pods — otherwise injection is skipped on first pod.
echo "⏳ Waiting 15 s for operator webhook to register injection config..."
sleep 15

# ── 7b. Patch probe timeouts for QEMU (Apple Silicon) ────────────────────────
# Under QEMU TCG emulation, containers start much slower than native.
# The operator and ActiveGate have tight default probe timeouts that cause
# unnecessary restarts on QEMU. Patch them to use generous timeouts.
step "Applying QEMU probe timeout patches"

if [[ "${IS_QEMU}" == "true" ]]; then
  # Patch Dynatrace operator startup probe (default timeoutSeconds=5 is too tight)
  if kubectl get deployment dynatrace-operator -n dynatrace &>/dev/null; then
    kubectl patch deployment dynatrace-operator -n dynatrace --type=json -p='[
      {"op":"replace","path":"/spec/template/spec/containers/0/startupProbe/timeoutSeconds","value":30},
      {"op":"replace","path":"/spec/template/spec/containers/0/startupProbe/failureThreshold","value":6},
      {"op":"replace","path":"/spec/template/spec/containers/0/startupProbe/periodSeconds","value":15}
    ]' 2>/dev/null && info "Operator startupProbe patched for QEMU." || true
  fi

  # ActiveGate: wait for StatefulSet then patch probe timeouts
  echo "⏳ Waiting for ActiveGate StatefulSet..."
  AG_TIMEOUT=60
  until kubectl get statefulset dynakube-activegate -n dynatrace &>/dev/null; do
    AG_TIMEOUT=$((AG_TIMEOUT - 5))
    if [[ "${AG_TIMEOUT}" -le 0 ]]; then
      warn "ActiveGate StatefulSet not yet created — skipping probe patch."
      break
    fi
    sleep 5
  done

  if kubectl get statefulset dynakube-activegate -n dynatrace &>/dev/null; then
    kubectl patch statefulset dynakube-activegate -n dynatrace --type=json -p='[
      {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":360},
      {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":6},
      {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":15},
      {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/periodSeconds","value":30},
      {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":360},
      {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":8},
      {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":15},
      {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/periodSeconds","value":30}
    ]' 2>/dev/null && info "ActiveGate probes patched for QEMU." || true
    kubectl delete pod -n dynatrace \
      -l app.kubernetes.io/name=dynakube,app.kubernetes.io/component=activegate \
      --ignore-not-found 2>/dev/null || true
  fi
else
  info "Native x86_64 host — skipping QEMU probe patches."
fi

# ── 8. Build app image into Colima's Docker daemon ───────────
step "Building todo-service Docker image"
export DOCKER_HOST="unix://${DOCKER_SOCK}"
echo "🔧 Using Docker socket: ${DOCKER_HOST}"
echo "🐳 Building todo-service:latest..."
docker build -t todo-service:latest .

# ── 9. Deploy the application ─────────────────────────────────
step "Deploying todo-service application"
kubectl apply -f k8s/namespace.yaml        # creates todo-app namespace with DT inject label
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-pvc.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/app-configmap.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
kubectl apply -f k8s/app-ingress.yaml

# Ensure the namespace carries the DT injection label (idempotent)
kubectl label namespace todo-app dynatrace.com/inject=true --overwrite

# Restart the deployment so any already-running pods pick up the OneAgent init container
kubectl rollout restart deployment/todo-service -n todo-app

# ── 10. Wait for pods to be ready ─────────────────────────────
step "Waiting for pods"
echo "⏳ PostgreSQL..."
kubectl rollout status deployment/postgres -n todo-app --timeout=300s

echo ""
echo "⏳ todo-service (Spring Boot startup takes ~10-12 min on QEMU — be patient)..."
echo "   Watch logs: kubectl logs -n todo-app -l app=todo-service -f"
kubectl rollout status deployment/todo-service -n todo-app --timeout=900s \
  || warn "todo-service not yet ready — Spring Boot is still starting. Check: kubectl get pods -n todo-app"

echo "⏳ Dynatrace ActiveGate (first install takes several minutes on QEMU)..."
kubectl -n dynatrace wait pod \
  --for=condition=ready \
  --selector=app.kubernetes.io/name=dynakube,app.kubernetes.io/component=activegate \
  --timeout=600s 2>/dev/null \
  || warn "ActiveGate not yet ready — still initialising. Check: kubectl get pods -n dynatrace"

# ── 11. Status summary ────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}✅  Setup complete!${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"
echo ""
echo "📊 Dynatrace namespace pods:"
kubectl get pods -n dynatrace
echo ""
echo "📊 todo-app namespace pods:"
kubectl get pods -n todo-app
echo ""
echo "🌐 Access todo-service (run in a separate terminal):"
echo "   kubectl port-forward svc/todo-service -n todo-app 8080:80"
echo "   curl http://localhost:8080/hello"
echo "   curl http://localhost:8080/api/todos"
echo ""
echo "🔗 Dynatrace Kubernetes view:"
echo "   https://${DT_ENV_ID}.apps.dynatrace.com/ui/apps/dynatrace.classic.kubernetes/"
echo ""
echo "📋 Validate observability data:  ./verify.sh"
echo ""
echo "⚠️  NOTE: First traces and logs may take 3–5 minutes to appear in Dynatrace."
echo "   Ensure 'Collect all container logs' is enabled:"
echo "   Settings > Log Monitoring > Log module feature flags"
