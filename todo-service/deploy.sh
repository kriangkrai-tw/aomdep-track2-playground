#!/usr/bin/env bash
# deploy.sh — Deprecated: use setup.sh for the full Dynatrace POC setup.
# This script still works for app-only deployments (no Dynatrace).
set -euo pipefail

# ============================================================
# deploy.sh — Build & deploy Todo Service to local minikube
# ============================================================

NAMESPACE="demo"
IMAGE_NAME="todo-service"
IMAGE_TAG="latest"

echo "🚀 Starting deployment to minikube..."

# 1. Ensure minikube is running
if ! minikube status | grep -q "Running"; then
  echo "Starting minikube..."
  minikube start
fi

# 2. Point Docker CLI at minikube's daemon so the image is available in-cluster
echo "🔧 Configuring Docker to use minikube's daemon..."
eval "$(minikube docker-env)"

# 3. Build the Docker image inside minikube's Docker context
echo "🐳 Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

# 4. Apply all manifests in order
echo "📦 Applying Kubernetes manifests..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-pvc.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/app-configmap.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
kubectl apply -f k8s/app-ingress.yaml

# 5. Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
kubectl rollout status deployment/postgres -n "${NAMESPACE}" --timeout=120s

# 6. Wait for the app to be ready
echo "⏳ Waiting for Todo Service to be ready..."
kubectl rollout status deployment/todo-service -n "${NAMESPACE}" --timeout=180s

# 7. Print access URL
echo ""
echo "✅ Deployment complete!"
echo ""
MINIKUBE_IP=$(minikube ip)
echo "📡 NodePort URL:  http://${MINIKUBE_IP}:30080/api/todos"
echo "❤️  Health check: http://${MINIKUBE_IP}:30080/actuator/health"
echo ""
echo "🌐 Ingress URL (add to /etc/hosts: ${MINIKUBE_IP} todo-app.local):"
echo "   http://todo-app.local/api/todos"
echo ""
echo "Or use: minikube service todo-service -n ${NAMESPACE} --url"
