#!/bin/bash

# Deploy prerequisites for DPF using helmfile from doca-platform
# For v25.7, we only need ArgoCD as other prerequisites are handled differently

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/env.sh"

# Configuration
DOCA_PLATFORM_PATH="${DOCA_PLATFORM_PATH:-$HOME/Coding/doca-platform}"
HELMFILE_VERSION="v1.1.2"

# Function to show usage
show_usage() {
    echo "Usage: $0 [all|argocd-only|argocd-helm]"
    echo ""
    echo "Options:"
    echo "  all         - Install all prerequisites using helmfile"
    echo "  argocd-only - Install only ArgoCD using helmfile (default)"
    echo "  argocd-helm - Install only ArgoCD using helm directly"
    echo ""
    echo "Example:"
    echo "  $0              # Install only ArgoCD using helmfile (default)"
    echo "  $0 argocd-only  # Install only ArgoCD using helmfile"
    echo "  $0 argocd-helm  # Install only ArgoCD using helm directly"
    echo "  $0 all          # Install all prerequisites using helmfile"
}

# Parse command line argument
INSTALL_MODE="${1:-argocd-only}"

# Deploy prerequisites
log [INFO] "Deploying DPF prerequisites..."

# Get kubeconfig
get_kubeconfig

# For argocd-helm mode, we don't need helmfile
if [[ "$INSTALL_MODE" != "argocd-helm" ]]; then
    # Check if helmfile exists
    if ! command -v helmfile &> /dev/null; then
        log [ERROR] "helmfile not found. Please install helmfile ${HELMFILE_VERSION}"
        log [INFO] "You can install it with: curl -Lo helmfile https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz"
        exit 1
    fi
    
    # Navigate to doca-platform helmfiles
    cd "${DOCA_PLATFORM_PATH}/deploy/helmfiles"
fi

case "$INSTALL_MODE" in
    all)
        log [INFO] "Installing all prerequisites (cert-manager, NFD, maintenance-operator, kamaji, and ArgoCD)..."
        helmfile --file prereqs.yaml sync
        ;;
    argocd-only)
        log [INFO] "Installing only ArgoCD for DPF v25.7..."
        helmfile --file prereqs.yaml --selector name=argo-cd sync
        ;;
    argocd-helm)
        log [INFO] "Installing ArgoCD using helm directly..."
        "${SCRIPT_DIR}/deploy-argocd.sh"
        exit 0
        ;;
    help|--help|-h)
        show_usage
        exit 0
        ;;
    *)
        log [ERROR] "Unknown mode: $INSTALL_MODE"
        show_usage
        exit 1
        ;;
esac

log [INFO] "Prerequisites deployment complete!"
log [INFO] "You can now deploy DPF operator using: make deploy-dpf"