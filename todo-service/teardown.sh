#!/usr/bin/env bash
# teardown.sh — Remove Dynatrace POC from Minikube
set -euo pipefail

STOP_MINIKUBE=false
for arg in "$@"; do
  [[ "${arg}" == "--stop-minikube" ]] && STOP_MINIKUBE=true
done

echo "🧹  Starting teardown..."

# ── Helm uninstalls ───────────────────────────────────────────────────────────
if helm status fluent-bit -n logging &>/dev/null; then
  echo "▶  Uninstalling Fluent Bit..."
  helm uninstall fluent-bit -n logging
else
  echo "✔  Fluent Bit not installed — skipping."
fi

if helm status dynatrace-operator -n dynatrace &>/dev/null; then
  echo "▶  Uninstalling Dynatrace Operator..."
  helm uninstall dynatrace-operator -n dynatrace
else
  echo "✔  Dynatrace Operator not installed — skipping."
fi

# ── Delete namespaces (this removes all resources inside them) ────────────────
for ns in demo logging dynatrace; do
  if kubectl get namespace "${ns}" &>/dev/null; then
    echo "▶  Deleting namespace '${ns}'..."
    kubectl delete namespace "${ns}" --timeout=2m
  else
    echo "✔  Namespace '${ns}' not found — skipping."
  fi
done

echo ""
echo "✅  Cluster resources removed."

# ── Optionally stop Minikube ──────────────────────────────────────────────────
if [[ "${STOP_MINIKUBE}" == "true" ]]; then
  echo "▶  Stopping Minikube..."
  minikube stop
  echo "✅  Minikube stopped."
else
  echo ""
  echo "ℹ️   Minikube is still running. Run 'minikube stop' to stop it,"
  echo "    or re-run with --stop-minikube to do it automatically."
fi
