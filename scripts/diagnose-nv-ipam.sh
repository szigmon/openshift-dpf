#!/bin/bash

# Diagnostic script for nv-ipam issues in DPU hosted cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

echo "======================================"
echo "NV-IPAM Diagnostics for DPU Cluster"
echo "======================================"

# Check if nvidia-k8s-ipam is deployed
log "Checking nvidia-k8s-ipam deployment..."
echo
if oc get dpuservice nvidia-k8s-ipam -n dpf-operator-system &>/dev/null; then
    info "✓ nvidia-k8s-ipam DPUService exists"
    oc get dpuservice nvidia-k8s-ipam -n dpf-operator-system -o wide
else
    error "✗ nvidia-k8s-ipam DPUService NOT FOUND"
fi

echo
log "Checking nvidia-k8s-ipam pods..."
echo
IPAM_PODS=$(oc get pods -n dpf-operator-system -l app=nvidia-k8s-ipam -o name 2>/dev/null || echo "")
if [ -n "$IPAM_PODS" ]; then
    info "✓ nvidia-k8s-ipam pods found:"
    oc get pods -n dpf-operator-system -l app=nvidia-k8s-ipam -o wide
else
    error "✗ No nvidia-k8s-ipam pods found"
fi

echo
log "Checking IPPool resources..."
echo
if oc get ippools -n dpf-operator-system &>/dev/null; then
    info "IPPools configured:"
    oc get ippools -n dpf-operator-system -o wide
else
    error "✗ No IPPools found or CRD not installed"
fi

echo
log "Checking NetworkAttachmentDefinition for iprequest..."
echo
if oc get net-attach-def iprequest -n dpf-operator-system &>/dev/null; then
    info "✓ iprequest NetworkAttachmentDefinition exists"
    oc get net-attach-def iprequest -n dpf-operator-system -o yaml | grep -A10 "spec:"
else
    error "✗ iprequest NetworkAttachmentDefinition NOT FOUND"
fi

echo
log "Checking CNI binaries on DPU nodes..."
echo
DPU_NODES=$(oc get nodes -l dpu-enabled=true -o name 2>/dev/null | cut -d/ -f2)
if [ -z "$DPU_NODES" ]; then
    warning "No DPU nodes found (nodes with label dpu-enabled=true)"
else
    for node in $DPU_NODES; do
        info "Checking node: $node"
        echo "  CNI binaries in /var/lib/cni/bin:"
        oc debug node/$node -- ls -la /host/var/lib/cni/bin/ 2>/dev/null | grep -E "(nv-ipam|multus)" || echo "  ✗ Failed to list CNI binaries"
        echo
    done
fi

echo
log "Checking HBN pod status..."
echo
HBN_PODS=$(oc get pods -n dpf-operator-system -l dpu.nvidia.com/service.id=hbn -o name 2>/dev/null || echo "")
if [ -n "$HBN_PODS" ]; then
    info "HBN pods status:"
    oc get pods -n dpf-operator-system -l dpu.nvidia.com/service.id=hbn -o wide
    
    # Check events for the first HBN pod
    FIRST_POD=$(echo "$HBN_PODS" | head -1 | cut -d/ -f2)
    if [ -n "$FIRST_POD" ]; then
        echo
        info "Recent events for pod $FIRST_POD:"
        oc describe pod "$FIRST_POD" -n dpf-operator-system | grep -A20 "Events:" | head -25
    fi
else
    warning "No HBN pods found"
fi

echo
echo "======================================"
echo "Diagnostic Summary"
echo "======================================"

# Summary
ISSUES=0

if ! oc get dpuservice nvidia-k8s-ipam -n dpf-operator-system &>/dev/null; then
    error "1. nvidia-k8s-ipam DPUService is missing"
    echo "   Fix: Run the fix-nv-ipam-hosted-cluster.sh script"
    ((ISSUES++))
fi

if ! oc get net-attach-def iprequest -n dpf-operator-system &>/dev/null; then
    error "2. iprequest NetworkAttachmentDefinition is missing"
    echo "   Fix: Run the fix-ipam-pools.sh script"
    ((ISSUES++))
fi

if [ -z "$IPAM_PODS" ]; then
    error "3. No nvidia-k8s-ipam pods are running"
    echo "   Fix: Check DPUService deployment status"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    info "✓ All basic checks passed. If HBN pods are still failing:"
    echo "  1. Check if nv-ipam binary exists in /var/lib/cni/bin on DPU nodes"
    echo "  2. Verify IPPool configuration matches your network setup"
    echo "  3. Check nvidia-k8s-ipam pod logs for errors"
else
    error "Found $ISSUES issue(s) that need to be fixed"
fi