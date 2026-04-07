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
  NODE_ARCH=$(kubectl get node -o jsonpath='{.items[0].status.nodeInfo.architecture}' 2>/dev/null || echo "unknown")
  if [[ "${NODE_ARCH}" == "arm64" ]]; then
    err "Minikube is running as ARM64. Dynatrace OneAgent requires x86_64 Linux."
    echo ""
    echo "  Fix: delete the cluster and re-run — setup.sh will use the qemu2 driver."
    echo "    minikube delete && ./setup.sh"
    echo "  Prerequisite: brew install qemu"
    exit 1
  fi
  info "Minikube is already running (arch: ${NODE_ARCH})."
else
  # Detect Apple Silicon — Dynatrace OneAgent requires x86_64 Linux.
  # --driver=docker with linux/amd64 emulation doesn't work (kicbase SEGV under Rosetta 2).
  # --driver=qemu2 with the amd64 ISO + x86_64 EFI firmware runs a real x86_64 VM via QEMU.
  HOST_ARCH=$(uname -m)
  MK_MEMORY=8192
  if [[ "${HOST_ARCH}" == "arm64" ]]; then
    if ! command -v qemu-system-x86_64 &>/dev/null; then
      err "QEMU is required on Apple Silicon (Dynatrace OneAgent requires x86_64 Linux)."
      echo "  Install QEMU:  brew install qemu"
      echo "  Then re-run:   ./setup.sh"
      exit 1
    fi
    # Locate the x86_64 EFI firmware installed by brew
    QEMU_FW=$(find /opt/homebrew /usr/local -name "edk2-x86_64-code.fd" 2>/dev/null | head -1)
    if [[ -z "${QEMU_FW}" ]]; then
      err "Could not find edk2-x86_64-code.fd. Ensure QEMU is installed via brew install qemu."
      exit 1
    fi
    MK_VERSION=$(minikube version --short 2>/dev/null | sed 's/^v//' || echo "1.38.1")
    # ISOs are attached to minikube GitHub releases starting from v1.32+.
    # For older versions, fall back to the latest known ISO.
    ISO_VERSION="${MK_VERSION}"
    if ! curl -sf --head \
      "https://github.com/kubernetes/minikube/releases/download/v${ISO_VERSION}/minikube-v${ISO_VERSION}-amd64.iso" \
      &>/dev/null; then
      ISO_VERSION="1.38.1"
    fi
    AMDISO="https://github.com/kubernetes/minikube/releases/download/v${ISO_VERSION}/minikube-v${ISO_VERSION}-amd64.iso"
    echo "🍎 Apple Silicon + QEMU detected — starting Minikube as x86_64 VM."
    echo "   ISO:      ${AMDISO}"
    echo "   Firmware: ${QEMU_FW}"
    minikube start --driver=qemu2 --cpus=4 --memory="${MK_MEMORY}" --disk-size=20g \
      --iso-url="${AMDISO}" \
      --qemu-firmware-path="${QEMU_FW}"
  else
    echo "🚀 Starting Minikube (4 CPU, ${MK_MEMORY} MB RAM, Docker driver)..."
    minikube start --cpus=4 --memory="${MK_MEMORY}" --driver=docker
  fi
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

# ── 7b. Minikube / Docker-driver workarounds for Dynatrace on Rosetta 2 ─
# The operator hard-codes amd64-only nodeAffinity and tight probe timeouts.
# The OneAgent also needs its CSI osagent volume host-path resolved correctly —
# on Minikube+Docker-driver the mountinfo paths use the Docker volume prefix
# which the OneAgent can't stat() through a symlink; a bind mount is required.
step "Applying Minikube/Apple-Silicon workarounds"
NODE_ARCH=$(kubectl get node -o jsonpath='{.items[0].status.nodeInfo.architecture}' 2>/dev/null || echo "unknown")
echo "Node architecture: ${NODE_ARCH}"

# ── 7b-i. ActiveGate: arch affinity + extended probe timeouts ────────────
echo "⏳ Waiting for ActiveGate StatefulSet..."
AG_TIMEOUT=60
until kubectl get statefulset dynakube-activegate -n dynatrace &>/dev/null; do
  AG_TIMEOUT=$((AG_TIMEOUT - 5))
  if [[ "${AG_TIMEOUT}" -le 0 ]]; then warn "ActiveGate StatefulSet not yet created — skipping."; break; fi
  sleep 5
done

if kubectl get statefulset dynakube-activegate -n dynatrace &>/dev/null; then
  if kubectl patch statefulset dynakube-activegate -n dynatrace --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/0/values","value":["amd64","arm64"]},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":180},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":4},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":10},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":180},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":6},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":10}
  ]'; then
    info "ActiveGate patched (arch affinity + extended probe timeouts)."
    kubectl delete pod -n dynatrace \
      -l app.kubernetes.io/name=dynakube,app.kubernetes.io/component=activegate \
      --ignore-not-found 2>/dev/null || true
  else
    warn "Could not patch ActiveGate StatefulSet."
  fi
fi

# ── 7b-ii. OneAgent DaemonSet: arch affinity ─────────────────────────────
echo "⏳ Waiting for OneAgent DaemonSet..."
OA_TIMEOUT=60
until kubectl get daemonset dynakube-oneagent -n dynatrace &>/dev/null; do
  OA_TIMEOUT=$((OA_TIMEOUT - 5))
  if [[ "${OA_TIMEOUT}" -le 0 ]]; then warn "OneAgent DaemonSet not yet created — skipping."; break; fi
  sleep 5
done

if kubectl get daemonset dynakube-oneagent -n dynatrace &>/dev/null; then
  if kubectl patch daemonset dynakube-oneagent -n dynatrace --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/0/values","value":["amd64","arm64"]}
  ]'; then
    info "OneAgent DaemonSet patched (arch affinity)."
  else
    warn "Could not patch OneAgent DaemonSet."
  fi
fi

# ── 7b-iii. OneAgent osagent bind mount (Minikube Docker-driver workaround) ─
# On Minikube+Docker-driver, /proc/self/mountinfo reports the CSI osagent volume
# source path using the Docker volume prefix (/var/lib/docker/volumes/minikube/_data/...).
# The OneAgent tries to stat() this path via /mnt/root/ and fails unless the path
# exists on the node. A bind mount makes both paths point to the same real inode.
OSAGENT_REAL="/var/lib/kubelet/plugins/csi.oneagent.dynatrace.com/data/_dynakubes/dynakube/osagent"
OSAGENT_MIRROR="/var/lib/docker/volumes/minikube/_data/lib/kubelet/plugins/csi.oneagent.dynatrace.com/data/_dynakubes/dynakube/osagent"

echo "⏳ Waiting for CSI osagent directory to be created by the operator..."
CSI_TIMEOUT=120
until minikube ssh -- "sudo test -d '${OSAGENT_REAL}'" 2>/dev/null; do
  CSI_TIMEOUT=$((CSI_TIMEOUT - 5))
  if [[ "${CSI_TIMEOUT}" -le 0 ]]; then
    warn "CSI osagent directory not found — skipping bind mount. OneAgent may fail to start."
    break
  fi
  sleep 5
done

if minikube ssh -- "sudo test -d '${OSAGENT_REAL}'" 2>/dev/null; then
  # Check if bind mount already exists (idempotent)
  if ! minikube ssh -- "sudo mountpoint -q '${OSAGENT_MIRROR}'" 2>/dev/null; then
    if minikube ssh -- "
      sudo mkdir -p '${OSAGENT_MIRROR}' && \
      sudo mount --bind '${OSAGENT_REAL}' '${OSAGENT_MIRROR}'
    " 2>/dev/null; then
      info "OneAgent osagent bind mount created."
    else
      warn "Could not create osagent bind mount — OneAgent may fail to start."
    fi
  else
    info "OneAgent osagent bind mount already exists."
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
