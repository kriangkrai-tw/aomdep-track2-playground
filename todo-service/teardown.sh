#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# teardown.sh — Remove Dynatrace operator and todo-service
#               from the local Minikube cluster.
#
# Usage:
#   ./teardown.sh                  # remove resources only
#   ./teardown.sh --stop-minikube  # also stop Minikube
# ============================================================

STOP_MINIKUBE=false

for arg in "$@"; do
  case "${arg}" in
    --stop-minikube) STOP_MINIKUBE=true ;;
    *) echo "Unknown flag: ${arg}"; exit 1 ;;
  esac
done

echo "🗑️  Deleting DynaKube CR..."
kubectl delete dynakube dynakube -n dynatrace --ignore-not-found

echo "🔐 Deleting dynakube secret..."
kubectl delete secret dynakube -n dynatrace --ignore-not-found

echo "⚙️  Uninstalling Dynatrace Operator (Helm)..."
if helm status dynatrace-operator --namespace dynatrace &>/dev/null; then
  helm uninstall dynatrace-operator --namespace dynatrace
else
  echo "   Dynatrace Operator not installed — skipping."
fi

echo "🗑️  Deleting todo-app namespace (and all resources within it)..."
kubectl delete namespace todo-app --ignore-not-found

echo "🗑️  Deleting dynatrace namespace (and all resources within it)..."
kubectl delete namespace dynatrace --ignore-not-found

if [[ "${STOP_MINIKUBE}" == "true" ]]; then
  echo "🛑 Stopping Minikube..."
  minikube stop
fi

echo ""
echo "✅  Teardown complete."
echo "   To restart from scratch: ./setup.sh"
