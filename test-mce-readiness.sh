#!/bin/bash

set -euo pipefail

# Load environment variables
source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "MCE Migration Readiness Check"
echo "=========================================="
echo ""

# Check existing HyperShift installation
echo -e "${YELLOW}1. Checking existing HyperShift installation...${NC}"
if oc get deployment -n hypershift hypershift-operator &>/dev/null; then
    echo -e "${GREEN}[✓]${NC} HyperShift operator is installed (standard deployment name)"
    echo "    Operator pods:"
    oc get pods -n hypershift | grep -E "NAME|hypershift-operator" || true
elif oc get deployment -n hypershift operator &>/dev/null; then
    echo -e "${GREEN}[✓]${NC} HyperShift operator is installed (deployment name: operator)"
    echo "    Operator pods:"
    oc get pods -n hypershift | grep -E "NAME|operator" || true
elif oc get namespace hypershift &>/dev/null; then
    echo -e "${YELLOW}[!]${NC} HyperShift namespace exists but operator deployment not found"
    echo "    Checking for other deployments:"
    oc get deployments -n hypershift 2>/dev/null || echo "    No deployments found"
else
    echo -e "${RED}[✗]${NC} HyperShift operator not found"
fi

# Check if MCE is already managing HyperShift
echo -e "\n${YELLOW}1a. Checking if MCE is managing HyperShift...${NC}"
if oc get mce -n multicluster-engine multiclusterengine -o jsonpath='{.spec.overrides.components[?(@.name=="hypershift")].enabled}' 2>/dev/null | grep -q "true"; then
    echo -e "${GREEN}[✓]${NC} MCE is already managing HyperShift"
else
    echo -e "${YELLOW}[!]${NC} MCE is not managing HyperShift"
fi

# Check existing HostedCluster
echo -e "\n${YELLOW}2. Checking existing HostedCluster...${NC}"
if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
    echo -e "${GREEN}[✓]${NC} HostedCluster '${HOSTED_CLUSTER_NAME}' exists"
    echo "    Status:"
    oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' || echo "Unknown"
else
    echo -e "${RED}[✗]${NC} HostedCluster '${HOSTED_CLUSTER_NAME}' not found"
fi

# Check control plane namespace
echo -e "\n${YELLOW}3. Checking control plane namespace...${NC}"
if oc get namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} &>/dev/null; then
    echo -e "${GREEN}[✓]${NC} Control plane namespace '${HOSTED_CONTROL_PLANE_NAMESPACE}' exists"
    echo "    Pod count: $(oc get pods -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --no-headers 2>/dev/null | wc -l)"
else
    echo -e "${RED}[✗]${NC} Control plane namespace not found"
fi

# Check MCE installation
echo -e "\n${YELLOW}4. Checking MCE installation...${NC}"
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    echo -e "${GREEN}[✓]${NC} MCE subscription exists"
    echo "    CSV Status:"
    oc get csv -n multicluster-engine | grep multicluster || echo "    No CSV found"
else
    echo -e "${YELLOW}[!]${NC} MCE not installed (will be installed during migration)"
fi

# Check storage class
echo -e "\n${YELLOW}5. Checking storage class...${NC}"
if oc get sc ${ETCD_STORAGE_CLASS} &>/dev/null; then
    echo -e "${GREEN}[✓]${NC} Storage class '${ETCD_STORAGE_CLASS}' exists"
else
    echo -e "${RED}[✗]${NC} Storage class '${ETCD_STORAGE_CLASS}' not found"
fi

# Check required secrets
echo -e "\n${YELLOW}6. Checking required files...${NC}"
if [ -f "${OPENSHIFT_PULL_SECRET}" ]; then
    echo -e "${GREEN}[✓]${NC} OpenShift pull secret file exists"
else
    echo -e "${RED}[✗]${NC} OpenShift pull secret file not found: ${OPENSHIFT_PULL_SECRET}"
fi

# Expand tilde in SSH_KEY path
SSH_KEY_EXPANDED="${SSH_KEY/#\~/$HOME}"

# Check if SSH_KEY already has .pub extension
if [[ "${SSH_KEY_EXPANDED}" =~ \.pub$ ]]; then
    # SSH_KEY already points to public key
    if [ -f "${SSH_KEY_EXPANDED}" ]; then
        echo -e "${GREEN}[✓]${NC} SSH public key file exists: ${SSH_KEY_EXPANDED}"
    else
        echo -e "${RED}[✗]${NC} SSH public key file not found: ${SSH_KEY_EXPANDED}"
    fi
else
    # SSH_KEY points to private key, check for .pub version
    if [ -f "${SSH_KEY_EXPANDED}.pub" ]; then
        echo -e "${GREEN}[✓]${NC} SSH public key file exists: ${SSH_KEY_EXPANDED}.pub"
    elif [ -f "${SSH_KEY_EXPANDED}" ]; then
        echo -e "${GREEN}[✓]${NC} SSH private key file exists: ${SSH_KEY_EXPANDED}"
        echo -e "${YELLOW}[!]${NC} Note: Public key expected at ${SSH_KEY_EXPANDED}.pub"
    else
        echo -e "${RED}[✗]${NC} SSH key file not found: ${SSH_KEY_EXPANDED}"
    fi
fi

# Check API VIP connectivity
echo -e "\n${YELLOW}7. Checking API VIP...${NC}"
if [ -n "${API_VIP}" ]; then
    echo -e "${GREEN}[✓]${NC} API VIP configured: ${API_VIP}"
else
    echo -e "${RED}[✗]${NC} API VIP not configured"
fi

# Summary
echo -e "\n${YELLOW}=========================================="
echo "Summary"
echo "==========================================${NC}"
echo ""
echo "Cluster name: ${CLUSTER_NAME}"
echo "Hosted cluster name: ${HOSTED_CLUSTER_NAME}"
echo "Base domain: ${BASE_DOMAIN}"
echo "Clusters namespace: ${CLUSTERS_NAMESPACE}"
echo "Control plane namespace: ${HOSTED_CONTROL_PLANE_NAMESPACE}"
echo ""
echo -e "${YELLOW}Ready for migration?${NC}"
echo "Run: ./scripts/migrate-to-mce.sh"
echo ""
echo "Options:"
echo "  --skip-backup    Skip backing up existing resources"
echo "  --force          Skip confirmation prompt"