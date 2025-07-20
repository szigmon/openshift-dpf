#!/bin/bash

# Deploy ArgoCD directly using helm for DPF v25.7
# This is a simplified alternative to using helmfile
#
# Values are externalized to: manifests/cluster-installation/argocd-values.yaml
#
# Note: ArgoCD Redis requires special SCC permissions on OpenShift to run as user 999
# This script grants existing OpenShift SCCs (anyuid and privileged) to ArgoCD service accounts

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/env.sh"

# Configuration
ARGOCD_NAMESPACE="dpf-operator-system"
ARGOCD_REPO="https://argoproj.github.io/argo-helm"

# Deploy ArgoCD
log [INFO] "Deploying ArgoCD for DPF v25.7..."

# Get kubeconfig by calling the cluster script
"${SCRIPT_DIR}/cluster.sh" get-kubeconfig

# Add ArgoCD helm repository
log [INFO] "Adding ArgoCD helm repository..."
helm repo add argoproj ${ARGOCD_REPO} || true
helm repo update

# Use external values file
ARGOCD_VALUES_FILE="${SCRIPT_DIR}/../manifests/dpf-installation/argocd-values.yaml"

# Verify values file exists
if [ ! -f "$ARGOCD_VALUES_FILE" ]; then
    log [ERROR] "ArgoCD values file not found: $ARGOCD_VALUES_FILE"
    exit 1
fi

log [INFO] "Using ArgoCD values from: $ARGOCD_VALUES_FILE"


# Install ArgoCD
log [INFO] "Installing ArgoCD chart version ${ARGOCD_CHART_VERSION}..."
helm upgrade --install argo-cd argoproj/argo-cd \
    --namespace ${ARGOCD_NAMESPACE} \
    --create-namespace \
    --version ${ARGOCD_CHART_VERSION} \
    --values ${ARGOCD_VALUES_FILE} \
    --wait

# Apply SCC permissions for ArgoCD
log [INFO] "Applying OpenShift SCCs for ArgoCD service accounts..."
kubectl apply -f ${SCRIPT_DIR}/../manifests/dpf-installation/argocd-scc.yaml

# Restart Redis deployment to pick up the new SCC
log [INFO] "Restarting Redis deployment to apply SCC..."
kubectl rollout restart deployment/argo-cd-argocd-redis -n ${ARGOCD_NAMESPACE} || true

# Wait for Redis to be ready
log [INFO] "Waiting for Redis to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argo-cd-argocd-redis -n ${ARGOCD_NAMESPACE} || true

log [INFO] "ArgoCD deployment complete!"
log [INFO] "You can now deploy DPF operator using: make deploy-dpf"