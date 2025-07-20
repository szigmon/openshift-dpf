#!/bin/bash
# Pre-flight check script for DPF v25.7 deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== DPF v25.7 Pre-flight Check ==="
echo

# Source environment
source scripts/env.sh

# Function to check requirement
check_requirement() {
    local name=$1
    local check_cmd=$2
    local fix_hint=$3
    
    echo -n "Checking $name... "
    if eval "$check_cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "  Fix: $fix_hint"
        return 1
    fi
}

# Track failures
FAILED=0

# Check environment variables
echo "=== Environment Variables ==="
check_requirement "MANIFESTS_DIR" "[ -n \"\$MANIFESTS_DIR\" ]" "Set MANIFESTS_DIR in .env" || ((FAILED++))
check_requirement "HELM_CHARTS_DIR" "[ -n \"\$HELM_CHARTS_DIR\" ]" "Set HELM_CHARTS_DIR in .env" || ((FAILED++))
check_requirement "DPF_VERSION" "[ \"\$DPF_VERSION\" = \"v25.7.0-beta.4\" ]" "Set DPF_VERSION=v25.7.0-beta.4 in env.sh" || ((FAILED++))

echo
echo "=== Required Files ==="
check_requirement "OpenShift pull secret" "[ -f \"\$OPENSHIFT_PULL_SECRET\" ]" "Create openshift_pull.json" || ((FAILED++))
check_requirement "DPF pull secret" "[ -f \"\$DPF_PULL_SECRET\" ]" "Create dpf_pull.json" || ((FAILED++))
check_requirement "SSH key" "[ -f \"\$SSH_KEY\" ]" "Generate SSH key: ssh-keygen -t rsa" || ((FAILED++))

echo
echo "=== Helm Values Files ==="
check_requirement "ArgoCD values" "[ -f \"\$HELM_CHARTS_DIR/argocd-values.yaml\" ]" "Missing argocd-values.yaml" || ((FAILED++))
check_requirement "Maintenance Operator values" "[ -f \"\$HELM_CHARTS_DIR/maintenance-operator-values.yaml\" ]" "Missing maintenance-operator-values.yaml" || ((FAILED++))
check_requirement "DPF Operator values" "[ -f \"\$HELM_CHARTS_DIR/dpf-operator-values.yaml\" ]" "Missing dpf-operator-values.yaml" || ((FAILED++))
check_requirement "OVN values" "[ -f \"\$HELM_CHARTS_DIR/ovn-values.yaml\" ]" "Missing ovn-values.yaml" || ((FAILED++))
check_requirement "OVN injector values" "[ -f \"\$HELM_CHARTS_DIR/ovn-values-with-injector.yaml\" ]" "Missing ovn-values-with-injector.yaml" || ((FAILED++))

echo
echo "=== Manifest Files ==="
check_requirement "ArgoCD SCC" "[ -f \"\$MANIFESTS_DIR/dpf-installation/argocd-scc.yaml\" ]" "Missing argocd-scc.yaml" || ((FAILED++))
check_requirement "NFD subscription" "[ -f \"\$MANIFESTS_DIR/cluster-installation/nfd-subscription.yaml\" ]" "Missing nfd-subscription.yaml" || ((FAILED++))
check_requirement "Cert Manager" "[ -f \"\$MANIFESTS_DIR/cluster-installation/openshift-cert-manager.yaml\" ]" "Missing openshift-cert-manager.yaml" || ((FAILED++))

echo
echo "=== Tools ==="
check_requirement "oc CLI" "command -v oc" "Install OpenShift CLI" || ((FAILED++))
check_requirement "helm" "command -v helm" "Install Helm 3" || ((FAILED++))
check_requirement "jq" "command -v jq" "Install jq: brew install jq" || ((FAILED++))
check_requirement "aicli" "command -v aicli" "Install aicli from assisted-installer" || ((FAILED++))

echo
echo "=== Network Connectivity ==="
check_requirement "ArgoCD Helm repo" "helm repo add argoproj https://argoproj.github.io/argo-helm &>/dev/null && helm repo update &>/dev/null" "Check internet connectivity" || ((FAILED++))
check_requirement "GitHub registry" "curl -s https://ghcr.io/v2/ | grep -q 'Docker Registry'" "Check GitHub registry access" || ((FAILED++))

echo
echo "=== NGC Authentication ==="
if [ -f "$DPF_PULL_SECRET" ]; then
    NGC_USERNAME=$(jq -r '.auths."nvcr.io".username // empty' "$DPF_PULL_SECRET" 2>/dev/null)
    NGC_PASSWORD=$(jq -r '.auths."nvcr.io".password // empty' "$DPF_PULL_SECRET" 2>/dev/null)
    
    check_requirement "NGC credentials in pull secret" "[ -n \"\$NGC_USERNAME\" ] && [ -n \"\$NGC_PASSWORD\" ] && [ \"\$NGC_USERNAME\" != \"null\" ]" "Add nvcr.io credentials to dpf_pull.json" || ((FAILED++))
fi

echo
echo "=== Summary ==="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Ready to deploy.${NC}"
    exit 0
else
    echo -e "${RED}$FAILED checks failed. Please fix the issues above before proceeding.${NC}"
    exit 1
fi