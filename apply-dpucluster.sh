#!/bin/bash

# Load environment variables
source scripts/env.sh

# Create processed DPUCluster manifest
cat > /tmp/static-dpucluster.yaml << EOF
apiVersion: provisioning.dpu.nvidia.com/v1alpha1
kind: DPUCluster
metadata:
  name: cluster
  namespace: dpf-operator-system
spec:
  type: static
  maxNodes: 10
  version: ${OPENSHIFT_VERSION}
  kubeconfig: ${HOSTED_CLUSTER_NAME}-admin-kubeconfig
EOF

echo "Applying static DPUCluster..."
oc apply -f /tmp/static-dpucluster.yaml

echo "Checking DPUCluster status..."
oc get dpucluster -A

echo "Done!" 