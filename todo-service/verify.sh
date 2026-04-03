#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# verify.sh — Validate Dynatrace observability for todo-service
#
# Required env vars:
#   DT_ENV_ID    — Dynatrace environment ID
#   DT_API_TOKEN — Dynatrace API token (logs.ingest + v2 read scopes)
# ============================================================

# ── Validate env vars ──────────────────────────────────────────
for var in DT_ENV_ID DT_API_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌  ERROR: Required environment variable '${var}' is not set." >&2
    exit 1
  fi
done

APP_PORT=18080

# ── Port-forward to todo-service ──────────────────────────────
echo "🔌 Starting port-forward to todo-service on localhost:${APP_PORT}..."
kubectl port-forward svc/todo-service -n todo-app "${APP_PORT}:80" &>/dev/null &
PF_PID=$!
# Clean up port-forward on exit
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT
sleep 3  # allow kubectl port-forward to establish

APP_URL="http://localhost:${APP_PORT}"

# ── Generate observability traffic ────────────────────────────
echo "📡 Sending 10 requests to GET /hello..."
for i in $(seq 1 10); do
  status=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/hello")
  echo "   request ${i}: HTTP ${status}"
done

echo "📡 Sending 3 requests to GET /error (expect 500)..."
for i in $(seq 1 3); do
  status=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/error")
  echo "   request ${i}: HTTP ${status}"
done

# ── Wait for data propagation ──────────────────────────────────
echo ""
echo "⏳ Waiting 60 seconds for traces and logs to propagate to Dynatrace..."
sleep 60

# ── Query Dynatrace Logs API ───────────────────────────────────
echo "🔍 Querying Dynatrace Logs API for namespace 'todo-app' (last 10 min)..."
DT_API="https://${DT_ENV_ID}.live.dynatrace.com/api"
LOG_QUERY="k8s.namespace.name%3D%22todo-app%22"

LOG_RESPONSE=$(curl -sf \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  "${DT_API}/v2/logs/search?query=${LOG_QUERY}&from=now-10m" \
  2>/dev/null) || LOG_RESPONSE='{"results":[]}'

LOG_COUNT=$(echo "${LOG_RESPONSE}" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results', [])))" \
  2>/dev/null || echo "0")

# ── Gather pod statuses ────────────────────────────────────────
OPERATOR_RUNNING=$(kubectl get pods -n dynatrace \
  -l app.kubernetes.io/name=dynatrace-operator \
  --no-headers 2>/dev/null | grep -c "Running" || true)

ACTIVEGATE_RUNNING=$(kubectl get pods -n dynatrace \
  --no-headers 2>/dev/null | grep -c "activegate" || true)

ONEAGENT_RUNNING=$(kubectl get pods -n dynatrace \
  --no-headers 2>/dev/null | grep -c "oneagent" || true)

TODO_STATUS=$(kubectl get pods -n todo-app -l app=todo-service \
  --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo "unknown")

INIT_NAMES=$(kubectl get pods -n todo-app -l app=todo-service \
  -o jsonpath='{.items[0].spec.initContainers[*].name}' 2>/dev/null || true)
HAS_AGENT=$(echo "${INIT_NAMES}" | grep -c "dynatrace" || true)

# ── Print verification report ─────────────────────────────────
pass() { echo "  ✅  $1: $2"; }
warn() { echo "  ⚠️   $1: $2"; }

echo ""
echo "════════════════════════════════════════════════════════"
echo "📊  Dynatrace POC Verification Report"
echo "════════════════════════════════════════════════════════"

if [[ "${OPERATOR_RUNNING}" -gt 0 ]]; then
  pass "Operator pods" "running (${OPERATOR_RUNNING} pod(s))"
else
  warn "Operator pods" "not found — kubectl get pods -n dynatrace"
fi

if [[ "${ACTIVEGATE_RUNNING}" -gt 0 ]]; then
  pass "ActiveGate" "running (${ACTIVEGATE_RUNNING} pod(s))"
else
  warn "ActiveGate" "not ready yet — may take 3-5 min on first install"
fi

if [[ "${ONEAGENT_RUNNING}" -gt 0 ]]; then
  pass "OneAgent DaemonSet" "running (${ONEAGENT_RUNNING} pod(s))"
else
  warn "OneAgent DaemonSet" "not ready yet"
fi

if [[ "${TODO_STATUS}" == "Running" ]]; then
  pass "todo-service pod" "Running"
else
  warn "todo-service pod" "status=${TODO_STATUS:-not found}"
fi

if [[ "${HAS_AGENT}" -gt 0 ]] 2>/dev/null; then
  pass "OneAgent injected" "init container '${INIT_NAMES}' present (cloudNativeFullStack CSI injection)"
else
  warn "OneAgent injected" "not detected — restart deployment or check namespace label"
  echo "         kubectl label ns todo-app dynatrace.com/inject=true --overwrite"
  echo "         kubectl rollout restart deployment/todo-service -n todo-app"
fi

if [[ "${LOG_COUNT}" -gt 0 ]]; then
  pass "Logs in Dynatrace" "${LOG_COUNT} log entries found in last 10 min"
else
  warn "Logs in Dynatrace" "none found yet — allow 3-5 min; verify 'Collect all container logs' is ON"
  echo "         Settings > Log Monitoring > Log module feature flags"
fi

echo ""
echo "🔗  Kubernetes view:  https://${DT_ENV_ID}.apps.dynatrace.com/ui/apps/dynatrace.classic.kubernetes/"
echo "🔗  Log viewer:       https://${DT_ENV_ID}.apps.dynatrace.com/ui/apps/dynatrace.classic.logs/"
echo "🔗  Services view:    https://${DT_ENV_ID}.apps.dynatrace.com/ui/apps/dynatrace.classic.services/"
echo ""
