#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# ============================================================
# setup.sh — Idempotent setup of Dynatrace + todo-service POC
#            on local Minikube
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
for cmd in kubectl helm minikube docker envsubst; do
  if ! command -v "${cmd}" &>/dev/null; then
    err "'${cmd}' is not installed. See README.md for installation instructions."
    exit 1
  fi
done
info "All prerequisites found."

# ── 3. Start Minikube ─────────────────────────────────────────
step "Starting Minikube"
if minikube status --format '{{.Host}}' 2>/dev/null | grep -q "Running"; then
  info "Minikube is already running."
else
  echo "🚀 Starting Minikube (4 CPU, 8 GB RAM, Docker driver)..."
  echo "   On Apple Silicon: Docker Desktop must have 'Use Rosetta for x86/amd64 emulation' enabled."
  minikube start --cpus=4 --memory=8192 --driver=docker
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

# ── 7b. Apple Silicon / ARM64 — fix ActiveGate arch affinity & probes ─
# The operator sets amd64-only nodeAffinity and probe timeouts that are
# too tight for Rosetta 2 emulation on Apple Silicon.
step "Patching ActiveGate for ARM64 compatibility"
NODE_ARCH=$(kubectl get node -o jsonpath='{.items[0].status.nodeInfo.architecture}' 2>/dev/null || echo "unknown")
echo "Detected node architecture: ${NODE_ARCH}"

# Wait up to 60 s for the StatefulSet to be created by the operator
echo "⏳ Waiting for ActiveGate StatefulSet to be created..."
AG_TIMEOUT=60
until kubectl get statefulset dynakube-activegate -n dynatrace &>/dev/null; do
  AG_TIMEOUT=$((AG_TIMEOUT - 5))
  if [[ "${AG_TIMEOUT}" -le 0 ]]; then
    warn "ActiveGate StatefulSet not yet created — skipping patch."
    break
  fi
  sleep 5
done

if kubectl get statefulset dynakube-activegate -n dynatrace &>/dev/null; then
  # Atomic patch: extend arch affinity to arm64 + increase probe timeouts for Rosetta
  if kubectl patch statefulset dynakube-activegate -n dynatrace --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/0/values","value":["amd64","arm64"]},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":180},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":4},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":10},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":180},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":6},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":10}
  ]'; then
    info "ActiveGate StatefulSet patched (arm64 affinity + extended probe timeouts)."
    # Bounce any running pod so it picks up the new probe settings
    kubectl delete pod -n dynatrace \
      -l app.kubernetes.io/name=dynakube,app.kubernetes.io/component=activegate \
      --ignore-not-found 2>/dev/null || true
  else
    warn "Could not patch ActiveGate StatefulSet — may need manual patching on Apple Silicon."
  fi
fi

# ── 8. Build app image inside Minikube's Docker daemon ───────
step "Building todo-service Docker image"
echo "🔧 Pointing Docker CLI at Minikube's daemon..."
# shellcheck disable=SC2046
eval "$(minikube docker-env)"
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
kubectl rollout status deployment/postgres -n todo-app --timeout=120s

echo "⏳ todo-service..."
kubectl rollout status deployment/todo-service -n todo-app --timeout=180s

echo "⏳ Dynatrace ActiveGate (first install may take several minutes)..."
kubectl -n dynatrace wait pod \
  --for=condition=ready \
  --selector=app.kubernetes.io/name=dynakube,app.kubernetes.io/component=activegate \
  --timeout=300s 2>/dev/null \
  || warn "ActiveGate not yet ready — it may still be initialising. Check: kubectl get pods -n dynatrace"

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
