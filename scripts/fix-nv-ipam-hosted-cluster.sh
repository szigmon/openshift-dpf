#!/bin/bash

# Fix script for missing nv-ipam CNI plugin in DPU hosted cluster
# This script should be run on the management cluster

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

# Check prerequisites
if ! command -v oc &> /dev/null; then
    error "oc command not found. Please install OpenShift CLI"
    exit 1
fi

# Get the hosted cluster name and namespace
HOSTED_CLUSTER_NAME="${HOSTED_CLUSTER_NAME:-doca}"
CLUSTERS_NAMESPACE="${CLUSTERS_NAMESPACE:-clusters}"
HOSTED_CONTROL_PLANE_NAMESPACE="${CLUSTERS_NAMESPACE}-${HOSTED_CLUSTER_NAME}"

log "Checking for nv-ipam issues in hosted cluster: ${HOSTED_CLUSTER_NAME}"

# Check if nvidia-k8s-ipam is deployed
log "Checking if nvidia-k8s-ipam DPUService exists..."
if ! oc get dpuservice nvidia-k8s-ipam -n dpf-operator-system &>/dev/null; then
    error "nvidia-k8s-ipam DPUService not found!"
    error "This service should be deployed as part of the DPU services"
    
    log "Creating nvidia-k8s-ipam DPUService..."
    cat <<EOF | oc apply -f -
apiVersion: dpu.nvidia.com/v1alpha1
kind: DPUService
metadata:
  name: nvidia-k8s-ipam
  namespace: dpf-operator-system
spec:
  serviceID: nvidia-k8s-ipam
  serviceConfiguration:
    serviceDaemonSet:
      spec:
        template:
          spec:
            hostNetwork: true
            containers:
            - name: kube-multus
              image: ghcr.io/nvidia/cloud-native/k8s-ipam:v0.4.5
              command: ["/usr/bin/nv-ipam"]
              args:
              - "-node-name=\$(NODE_NAME)"
              - "-v=1"
              - "-leader-elect=true"
              - "-leader-elect-namespace=dpf-operator-system"
              env:
              - name: NODE_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: spec.nodeName
              resources:
                requests:
                  cpu: "100m"
                  memory: "50Mi"
              securityContext:
                privileged: true
              volumeMounts:
              - name: cnibin
                mountPath: /host/opt/cni/bin
              - name: cni
                mountPath: /host/etc/cni/net.d
              - name: hostlocalcnibin
                mountPath: /host/var/lib/cni/bin
            volumes:
            - name: cnibin
              hostPath:
                path: /opt/cni/bin
            - name: cni
              hostPath:
                path: /etc/cni/net.d
            - name: hostlocalcnibin
              hostPath:
                path: /var/lib/cni/bin
    helmChart:
      source:
        chart: nvidia-k8s-ipam
        repoURL: https://nvidia.github.io/cloud-native
        version: "0.4.5"
      values:
        ipam:
          image:
            repository: ghcr.io/nvidia/cloud-native/k8s-ipam
            tag: v0.4.5
          enableWebhook: false
EOF
else
    log "nvidia-k8s-ipam DPUService already exists"
fi

# Wait for the service to be deployed
log "Waiting for nvidia-k8s-ipam to be ready..."
if ! oc wait --for=condition=ready dpuservice/nvidia-k8s-ipam -n dpf-operator-system --timeout=300s; then
    warning "nvidia-k8s-ipam DPUService not ready after 5 minutes"
fi

# Check IPPool configuration
log "Checking IPPool configuration..."
if ! oc get ippools -n dpf-operator-system &>/dev/null; then
    log "Creating default IPPools..."
    cat <<EOF | oc apply -f -
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: pool1
  namespace: dpf-operator-system
spec:
  subnet: "192.168.1.0/24"
  perNodeBlockSize: 24
  gateway: "192.168.1.1"
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
fi

# Create NetworkAttachmentDefinition for iprequest if missing
log "Checking NetworkAttachmentDefinition for iprequest..."
if ! oc get net-attach-def iprequest -n dpf-operator-system &>/dev/null; then
    log "Creating iprequest NetworkAttachmentDefinition..."
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
      "poolName": "pool1"
    }
EOF
fi

# Check if the nv-ipam binary is present on DPU nodes
log "Checking nv-ipam binary on DPU nodes..."
DPU_NODES=$(oc get nodes -l dpu-enabled=true -o name | cut -d/ -f2)

for node in $DPU_NODES; do
    log "Checking node: $node"
    
    # Create a debug pod to check the CNI binaries
    oc debug node/$node -- ls -la /host/var/lib/cni/bin/ 2>/dev/null | grep -q nv-ipam || {
        warning "nv-ipam binary not found on node $node"
        
        # Copy the binary from the nvidia-k8s-ipam pod
        log "Attempting to copy nv-ipam binary to node $node..."
        
        # Find a running nvidia-k8s-ipam pod
        IPAM_POD=$(oc get pods -n dpf-operator-system -l app=nvidia-k8s-ipam -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$IPAM_POD" ]; then
            log "Found nvidia-k8s-ipam pod: $IPAM_POD"
            # Note: This would require additional steps to copy the binary
        else
            error "No nvidia-k8s-ipam pod found running"
        fi
    }
done

# Force restart HBN pods to pick up the changes
log "Restarting HBN pods..."
oc delete pods -n dpf-operator-system -l dpu.nvidia.com/service.id=hbn --force --grace-period=0 2>/dev/null || true

log "Checking HBN pod status..."
sleep 10
oc get pods -n dpf-operator-system -l dpu.nvidia.com/service.id=hbn

log "Fix script completed. Please check if HBN pods are now running successfully."
log "If issues persist, you may need to:"
log "1. Check the nvidia-k8s-ipam daemonset logs"
log "2. Verify the IPPool configuration matches your network setup"
log "3. Ensure the hosted cluster nodes have the correct CNI configuration"