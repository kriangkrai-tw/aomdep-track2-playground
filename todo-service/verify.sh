#!/usr/bin/env bash
# verify.sh — Smoke-test the Dynatrace POC
set -euo pipefail

# ── Validate env vars ─────────────────────────────────────────────────────────
missing=0
for var in DT_ENV_ID DT_API_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable '${var}' is not set." >&2
    missing=1
  fi
done
[[ "${missing}" -eq 0 ]] || { echo "Aborting: set the missing variables and retry." >&2; exit 1; }

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"   # "pass" or "fail"
  local detail="${3:-}"
  if [[ "${result}" == "pass" ]]; then
    echo "  ✅  ${label}"
    PASS=$((PASS + 1))
  else
    echo "  ❌  ${label}${detail:+  (${detail})}"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  🔍  Dynatrace POC Verification"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── 1. Check Dynatrace Operator pod ──────────────────────────────────────────
echo "▶  Checking Dynatrace Operator..."
DT_OP_READY=$(kubectl get pods -n dynatrace \
  -l app.kubernetes.io/name=dynatrace-operator \
  --field-selector=status.phase=Running \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${DT_OP_READY}" -gt 0 ]]; then
  check "Dynatrace Operator running" "pass"
else
  check "Dynatrace Operator running" "fail" "no Running pods in dynatrace ns"
fi

# ── 2. Check Fluent Bit DaemonSet ─────────────────────────────────────────────
echo "▶  Checking Fluent Bit..."
FB_DESIRED=$(kubectl get daemonset fluent-bit -n logging \
  -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
FB_READY=$(kubectl get daemonset fluent-bit -n logging \
  -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
if [[ "${FB_READY}" -ge "${FB_DESIRED}" && "${FB_DESIRED}" -gt 0 ]]; then
  check "Fluent Bit DaemonSet ready (${FB_READY}/${FB_DESIRED})" "pass"
else
  check "Fluent Bit DaemonSet ready (${FB_READY}/${FB_DESIRED})" "fail"
fi

# ── 3. Check demo app pod ─────────────────────────────────────────────────────
echo "▶  Checking demo app pod..."
APP_READY=$(kubectl get pods -n demo \
  -l app=todo-service \
  --field-selector=status.phase=Running \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${APP_READY}" -gt 0 ]]; then
  check "todo-service pod running" "pass"
else
  check "todo-service pod running" "fail" "no Running pods in demo ns"
fi

# ── 4. Generate traffic & check HTTP responses ────────────────────────────────
echo "▶  Generating traffic against demo app..."

# On Docker driver the NodePort IP is unreachable; use kubectl port-forward instead
MINIKUBE_DRIVER="$(minikube profile list -o json 2>/dev/null \
  | python3 -c "import sys,json; p=json.load(sys.stdin)['valid']; print(p[0]['Config']['Driver'])" 2>/dev/null || echo "unknown")"

PF_PID=""
if [[ "${MINIKUBE_DRIVER}" == "docker" ]]; then
  kubectl port-forward svc/todo-service 18080:80 -n demo &>/dev/null &
  PF_PID=$!
  sleep 3
  BASE_URL="http://127.0.0.1:18080"
else
  MINIKUBE_IP="$(minikube ip 2>/dev/null || echo '')"
  BASE_URL="http://${MINIKUBE_IP}:30080"
fi

HTTP_OK=false
if [[ -n "${BASE_URL}" ]]; then
  for _ in $(seq 1 5); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time 5 "${BASE_URL}/api/todos" 2>/dev/null || echo "000")
    echo "    GET /api/todos → HTTP ${STATUS}"
    [[ "${STATUS}" == "200" ]] && HTTP_OK=true
    sleep 1
  done
  # Trigger an intentional 404 to produce an error log
  curl -s -o /dev/null --max-time 5 "${BASE_URL}/api/todos/00000000-0000-0000-0000-000000000000" || true
fi

# Clean up port-forward if we started one
[[ -n "${PF_PID}" ]] && kill "${PF_PID}" 2>/dev/null || true

if "${HTTP_OK}"; then
  check "Demo app responds HTTP 200" "pass"
else
  check "Demo app responds HTTP 200" "fail" "curl to ${BASE_URL}/api/todos failed"
fi

# ── 5. Check Dynatrace Log Ingest for recent demo logs ────────────────────────
echo "▶  Querying Dynatrace Logs API..."
DT_LOG_URL="https://${DT_ENV_ID}.live.dynatrace.com/api/v2/logs/search"
LOG_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time 10 \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  "${DT_LOG_URL}?query=k8s.namespace.name%3D%22demo%22&limit=5" 2>/dev/null || echo "000")

if [[ "${LOG_RESPONSE}" == "200" ]]; then
  LOG_COUNT=$(curl -s \
    --max-time 10 \
    -H "Authorization: Api-Token ${DT_API_TOKEN}" \
    "${DT_LOG_URL}?query=k8s.namespace.name%3D%22demo%22&limit=5" \
    2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',d.get('logs',[]))))" 2>/dev/null || echo "0")
  if [[ "${LOG_COUNT:-0}" -gt 0 ]]; then
    check "Logs visible in Dynatrace (${LOG_COUNT} entries)" "pass"
  else
    check "Logs visible in Dynatrace" "fail" \
      "API returned 200 but 0 results — logs may not have arrived yet (wait ~2 min)"
  fi
else
  check "Dynatrace Logs API reachable" "fail" "HTTP ${LOG_RESPONSE}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "═══════════════════════════════════════════════════════"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo "  Tip: If logs are not yet visible, wait 2–3 minutes and re-run verify.sh."
  echo "  Dynatrace UI: https://${DT_ENV_ID}.live.dynatrace.com/ui/logs"
  echo ""
  exit 1
fi
