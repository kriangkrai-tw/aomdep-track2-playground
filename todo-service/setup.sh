#!/usr/bin/env bash
# setup.sh — Full Dynatrace POC setup on Minikube (idempotent, re-runnable)
set -euo pipefail

# ── 1. Validate required env vars ────────────────────────────────────────────
missing=0
for var in DT_ENV_ID DT_API_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable '${var}' is not set." >&2
    missing=1
  fi
done
[[ "${missing}" -eq 0 ]] || { echo "Aborting: set the missing variables and retry." >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

echo "🚀  Starting Dynatrace POC setup..."

# ── 2. Start Minikube if not running ─────────────────────────────────────────
if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "▶  Starting Minikube (4 CPUs, 8 GB RAM, docker driver)..."
  minikube start --cpus=4 --memory=8192 --driver=docker
else
  echo "✔  Minikube is already running."
fi

# ── 3. Install Dynatrace Operator via Helm ────────────────────────────────────
echo ""
echo "▶  Installing Dynatrace Operator..."
helm repo add dynatrace \
  https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable \
  2>/dev/null || true
helm repo update dynatrace

# Apply CRDs directly from the release — Helm bundles them as templates,
# so helm show crds returns nothing and helm upgrade skips them.
echo "  Applying Dynatrace CRDs..."
DT_CHART_VERSION=$(helm list -n dynatrace --filter dynatrace-operator -o json 2>/dev/null \
  | python3 -c "import sys,json; c=json.load(sys.stdin); print(c[0]['chart'].split('-')[-1])" 2>/dev/null || true)
if [[ -n "${DT_CHART_VERSION}" ]]; then
  kubectl apply -f "https://github.com/Dynatrace/dynatrace-operator/releases/download/v${DT_CHART_VERSION}/dynatrace-operator-crd.yaml"
else
  kubectl apply -f "https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/dynatrace-operator-crd.yaml"
fi

helm upgrade --install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --create-namespace \
  --atomic \
  --timeout 3m \
  --set platform=kubernetes

# ── 4. Create Dynatrace token secret ─────────────────────────────────────────
echo ""
echo "▶  Creating Dynatrace API token secret..."
kubectl create secret generic dynakube \
  --namespace dynatrace \
  --from-literal=apiToken="${DT_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ── 5. Apply DynaKube CR (applicationMonitoring, useCSIDriver: false) ─────────
echo ""
echo "▶  Applying DynaKube CR..."

# Wait for the CRD to be fully established before creating an instance of it
echo "⏳  Waiting for DynaKube CRD to be established..."
kubectl wait --for=condition=Established \
  crd/dynakubes.dynatrace.com --timeout=60s

# Bust kubectl's API discovery cache so it picks up the new CRD group
rm -rf "${HOME}/.kube/cache/discovery/"

# Detect the highest served version of the DynaKube CRD dynamically
DYNAKUBE_VERSION=$(kubectl get crd dynakubes.dynatrace.com \
  -o jsonpath='{range .spec.versions[?(@.served==true)]}{.name}{"\n"}{end}' \
  | sort -V | tail -1)
echo "  Using DynaKube API version: dynatrace.com/${DYNAKUBE_VERSION}"

envsubst < "${K8S_DIR}/dynakube.yaml" \
  | sed "s|dynatrace.com/v1beta[0-9]*|dynatrace.com/${DYNAKUBE_VERSION}|" \
  | kubectl apply -f -

# Wait for operator webhook to be ready before deploying instrumented pods
echo "⏳  Waiting for Dynatrace Operator webhook..."
kubectl rollout status deployment/dynatrace-operator \
  --namespace dynatrace --timeout=3m

# ── 6. Install Fluent Bit via Helm ────────────────────────────────────────────
echo ""
echo "▶  Installing Fluent Bit..."
helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null || true
helm repo update fluent

# Adopt any pre-existing Fluent Bit cluster-scoped RBAC not yet owned by Helm
# (happens when a prior manual install left resources behind)
for resource_type in clusterrole clusterrolebinding; do
  if kubectl get "${resource_type}" fluent-bit &>/dev/null; then
    kubectl annotate "${resource_type}" fluent-bit \
      meta.helm.sh/release-name=fluent-bit \
      meta.helm.sh/release-namespace=logging \
      --overwrite 2>/dev/null || true
    kubectl label "${resource_type}" fluent-bit \
      app.kubernetes.io/managed-by=Helm \
      --overwrite 2>/dev/null || true
  fi
done

FLUENT_BIT_VALUES_TMP="$(mktemp /tmp/fluent-bit-values-XXXXXX.yaml)"
trap 'rm -f "${FLUENT_BIT_VALUES_TMP}"' EXIT

# SC2016 intentional: single-quoted string is the envsubst variable allowlist
# shellcheck disable=SC2016
envsubst '${DT_ENV_ID} ${DT_API_TOKEN}' < "${K8S_DIR}/fluent-bit-values.yaml" > "${FLUENT_BIT_VALUES_TMP}"

helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace logging \
  --create-namespace \
  --values "${FLUENT_BIT_VALUES_TMP}" \
  --atomic \
  --timeout 3m

# ── 7. Build & deploy the demo app (todo-service) ────────────────────────────
echo ""
echo "▶  Building todo-service image inside Minikube's Docker..."
eval "$(minikube docker-env)"
docker build -t todo-service:latest "${SCRIPT_DIR}" -q

echo "▶  Deploying demo app to 'demo' namespace..."

# Clean up the old todo-app namespace if it exists (renamed to demo)
if kubectl get namespace todo-app &>/dev/null; then
  echo "  Removing legacy 'todo-app' namespace..."
  kubectl delete namespace todo-app --timeout=2m
fi

kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/postgres-secret.yaml"
kubectl apply -f "${K8S_DIR}/postgres-pvc.yaml"
kubectl apply -f "${K8S_DIR}/postgres-deployment.yaml"
kubectl apply -f "${K8S_DIR}/postgres-service.yaml"
kubectl apply -f "${K8S_DIR}/app-configmap.yaml"
kubectl apply -f "${K8S_DIR}/app-deployment.yaml"
# NodePort services can't be patched when the port is already allocated elsewhere;
# delete first to guarantee a clean apply.
kubectl delete service todo-service -n demo --ignore-not-found
kubectl apply -f "${K8S_DIR}/app-service.yaml"

# ── 8. Wait for all pods ──────────────────────────────────────────────────────
echo ""
echo "⏳  Waiting for PostgreSQL (up to 2 min)..."
kubectl rollout status deployment/postgres -n demo --timeout=2m

echo "⏳  Waiting for todo-service (up to 3 min)..."
kubectl rollout status deployment/todo-service -n demo --timeout=3m

echo "⏳  Waiting for Fluent Bit DaemonSet (up to 2 min)..."
kubectl rollout status daemonset/fluent-bit -n logging --timeout=2m

# ── 9. Print status summary ───────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅  POC setup complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Pod status:"
kubectl get pods -n dynatrace --no-headers 2>/dev/null | awk '{printf "    dynatrace/%-40s %s\n", $1, $3}'
kubectl get pods -n logging --no-headers   2>/dev/null | awk '{printf "    logging/%-43s %s\n",   $1, $3}'
kubectl get pods -n demo --no-headers      2>/dev/null | awk '{printf "    demo/%-46s %s\n",      $1, $3}'
echo ""

MINIKUBE_DRIVER="$(minikube profile list -o json 2>/dev/null \
  | python3 -c "import sys,json; p=json.load(sys.stdin)['valid']; print(p[0]['Config']['Driver'])" 2>/dev/null || echo "unknown")"

if [[ "${MINIKUBE_DRIVER}" == "docker" ]]; then
  echo "  ⚠️   Docker driver detected — NodePort is not directly reachable on macOS."
  echo "  Run this in a new terminal to open a localhost tunnel:"
  echo ""
  echo "    minikube service todo-service -n demo"
  echo ""
  echo "  Or get just the URL (keep the process running):"
  echo ""
  echo "    minikube service todo-service -n demo --url"
else
  MINIKUBE_IP="$(minikube ip)"
  echo "  📡  NodePort URL:   http://${MINIKUBE_IP}:30080/api/todos"
  echo "  ❤️   Health check:  http://${MINIKUBE_IP}:30080/actuator/health"
fi

echo ""
echo "  Dynatrace tenant:  https://${DT_ENV_ID}.live.dynatrace.com"
echo "═══════════════════════════════════════════════════════"
