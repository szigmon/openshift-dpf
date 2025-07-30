#!/bin/bash

set -euo pipefail

echo "=== Using Existing HyperShift Installation ==="
echo ""

# Check if HyperShift CRDs still exist
echo "1. Checking for HyperShift CRDs..."
oc get crd | grep hypershift.openshift.io || echo "No HyperShift CRDs found"

# Check if we can create a HostedCluster directly
echo ""
echo "2. Checking if we can use HyperShift directly..."
if oc get crd hostedclusters.hypershift.openshift.io &>/dev/null; then
    echo "✓ HyperShift CRDs are available!"
    echo ""
    echo "3. Creating HyperShift operator namespace..."
    oc create namespace hypershift 2>/dev/null || echo "Namespace already exists"
    
    echo ""
    echo "4. Installing HyperShift operator directly..."
    # Use the hypershift CLI if available
    if command -v hypershift &>/dev/null; then
        echo "Using hypershift CLI to install operator..."
        hypershift install --hypershift-image=${HYPERSHIFT_IMAGE:-quay.io/hypershift/hypershift-operator:latest}
    else
        echo "hypershift CLI not found. Creating operator manually..."
        cat > /tmp/hypershift-operator.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: hypershift
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: operator
  namespace: hypershift
spec:
  replicas: 1
  selector:
    matchLabels:
      app: operator
  template:
    metadata:
      labels:
        app: operator
    spec:
      serviceAccountName: operator
      containers:
      - name: operator
        image: quay.io/hypershift/hypershift-operator:latest
        imagePullPolicy: Always
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: operator
  namespace: hypershift
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hypershift-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: operator
  namespace: hypershift
EOF
        oc apply -f /tmp/hypershift-operator.yaml
    fi
    
    echo ""
    echo "5. You can now proceed with creating the HostedCluster"
    echo "   Run: make deploy-hosted-cluster"
else
    echo "✗ HyperShift CRDs not found. MCE installation is required."
fi