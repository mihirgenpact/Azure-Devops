#!/usr/bin/env bash
set -euo pipefail

# Run this once against the AKS cluster (after `az aks get-credentials`).

echo "Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Installing Secrets Store CSI driver + Azure provider (for Key Vault access)..."
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm repo update
helm upgrade --install csi-secrets-store-provider-azure \
  csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
  --namespace kube-system

echo "Registering the production Argo CD Application..."
kubectl apply -f ../gitops/argocd-application-production.yaml

echo ""
echo "Argo CD installed. Get the initial admin password with:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Then port-forward to reach the UI:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
