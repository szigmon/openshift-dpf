#!/bin/bash

# Fix script for IPAM pools and NetworkAttachmentDefinition setup
# This ensures proper IP allocation for HBN and other DPU services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Configuration
HBN_OVN_NETWORK="${HBN_OVN_NETWORK:-10.0.120.0/22}"

log "Setting up IPAM pools for HBN OVN network: ${HBN_OVN_NETWORK}"

# First ensure the CRDs exist
log "Checking if IPPool CRD exists..."
if ! oc get crd ippools.nv-ipam.nvidia.com &>/dev/null; then
    error "IPPool CRD not found. nvidia-k8s-ipam may not be properly installed."
    exit 1
fi

# Create the IPPools for HBN
log "Creating IPPools for HBN..."
cat <<EOF | oc apply -f -
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: pool1
  namespace: dpf-operator-system
spec:
  subnet: "${HBN_OVN_NETWORK}"
  perNodeBlockSize: 24
  gateway: "$(echo ${HBN_OVN_NETWORK} | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".1"}')"
  exclusions:
  - startIP: "$(echo ${HBN_OVN_NETWORK} | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".1"}')"
    endIP: "$(echo ${HBN_OVN_NETWORK} | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".10"}')"
---
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: loopback
  namespace: dpf-operator-system
spec:
  subnet: "127.0.0.0/8"
  perNodeBlockSize: 32
EOF

# Create CIDRPool for more advanced allocation
log "Creating CIDRPool configuration..."
cat <<EOF | oc apply -f -
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: CIDRPool
metadata:
  name: cidrpool1
  namespace: dpf-operator-system
spec:
  cidr: "${HBN_OVN_NETWORK}"
  gatewayIndex: 1
  perNodeNetworkPrefix: 24
  excludeSubnets:
  - "$(echo ${HBN_OVN_NETWORK} | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".0/29"}')"
---
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: CIDRPool
metadata:
  name: loopback-cidr
  namespace: dpf-operator-system
spec:
  cidr: "127.0.0.0/8"
  perNodeNetworkPrefix: 32
EOF

# Create the NetworkAttachmentDefinition for iprequest
log "Creating NetworkAttachmentDefinition for iprequest..."
cat <<EOF | oc apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: iprequest
  namespace: dpf-operator-system
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "iprequest",
      "type": "nv-ipam",
      "daemonSocket": "/run/nvidia/nv-ipam.sock",
      "daemonCallTimeoutSeconds": 10,
      "confDir": "/etc/cni/net.d/nv-ipam.d",
      "logFile": "/var/log/nv-ipam.log",
      "logLevel": "debug"
    }
EOF

# Ensure the nvidia-k8s-ipam daemonset is running
log "Checking nvidia-k8s-ipam daemonset..."
if oc get daemonset -n dpf-operator-system -l app=nvidia-k8s-ipam &>/dev/null; then
    log "nvidia-k8s-ipam daemonset found, restarting pods..."
    oc rollout restart daemonset -n dpf-operator-system -l app=nvidia-k8s-ipam
    oc rollout status daemonset -n dpf-operator-system -l app=nvidia-k8s-ipam --timeout=300s
else
    warning "nvidia-k8s-ipam daemonset not found"
fi

# Check the status
log "Checking IPPool status..."
oc get ippools -n dpf-operator-system

log "Checking CIDRPool status..."
oc get cidrpools -n dpf-operator-system 2>/dev/null || warning "CIDRPool CRD might not be available"

log "IPAM configuration completed."
log "HBN pods should now be able to attach to the iprequest network."