#!/bin/bash

set -euo pipefail

echo "=== Starting Fresh MCE Installation ==="
echo ""

# Step 1: Check current namespace status
echo "1. Checking namespace status..."
if oc get namespace multicluster-engine &>/dev/null; then
    PHASE=$(oc get namespace multicluster-engine -o jsonpath='{.status.phase}')
    echo "   Namespace exists in phase: $PHASE"
    
    if [ "$PHASE" = "Terminating" ]; then
        echo "   Namespace is stuck terminating. Let's force remove it."
        
        # Get namespace JSON and remove finalizers
        echo "   Removing finalizers..."
        kubectl get namespace multicluster-engine -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/multicluster-engine/finalize" -f - || true
        
        # Try direct API call to remove finalizers
        kubectl proxy &
        PROXY_PID=$!
        sleep 2
        
        curl -k -H "Content-Type: application/json" -X PUT --data-binary @- http://127.0.0.1:8001/api/v1/namespaces/multicluster-engine/finalize << EOF
{
  "kind": "Namespace",
  "apiVersion": "v1",
  "metadata": {
    "name": "multicluster-engine"
  },
  "spec": {
    "finalizers": []
  }
}
EOF
        
        kill $PROXY_PID 2>/dev/null || true
        
        # Force delete
        oc delete namespace multicluster-engine --force --grace-period=0 2>/dev/null || true
        
        echo "   Waiting for namespace to be gone..."
        retries=30
        while [ $retries -gt 0 ] && oc get namespace multicluster-engine &>/dev/null; do
            echo -n "."
            sleep 2
            ((retries--))
        done
        echo ""
    fi
fi

# Also check hypershift namespace
if oc get namespace hypershift &>/dev/null; then
    echo "   Removing hypershift namespace..."
    oc delete namespace hypershift --force --grace-period=0 2>/dev/null || true
fi

# Step 2: Clean up any cluster-scoped resources
echo ""
echo "2. Cleaning cluster-scoped resources..."
# Delete CRDs
for crd in $(oc get crd -o name | grep -E "multicluster|hypershift"); do
    echo "   Deleting $crd"
    oc delete $crd --force --grace-period=0 2>/dev/null || true
done

# Delete cluster roles and bindings
for cr in $(oc get clusterrole -o name | grep -E "multicluster-engine|hypershift"); do
    oc delete $cr --force --grace-period=0 2>/dev/null || true
done

for crb in $(oc get clusterrolebinding -o name | grep -E "multicluster-engine|hypershift"); do
    oc delete $crb --force --grace-period=0 2>/dev/null || true
done

# Wait a bit for cleanup
sleep 5

# Step 3: Create just the basic resources
echo ""
echo "3. Creating namespace..."
cat << 'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: multicluster-engine
EOF

# Wait for namespace to be ready
echo "   Waiting for namespace to be ready..."
retries=30
while [ $retries -gt 0 ]; do
    PHASE=$(oc get namespace multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$PHASE" = "Active" ]; then
        echo "   ✓ Namespace is active"
        break
    fi
    echo -n "."
    sleep 1
    ((retries--))
done

echo ""
echo "4. Creating operator group..."
cat << 'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine-operatorgroup
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
EOF

echo ""
echo "5. Creating subscription..."
cat << 'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: stable-2.8
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo ""
echo "✓ Basic resources created!"
echo ""
echo "Now wait for the operator to install. Monitor with:"
echo "  watch 'oc get subscription,installplan,csv -n multicluster-engine'"
echo ""
echo "Once the CSV shows phase 'Succeeded', create the MCE instance:"
echo ""
echo "cat << 'EOF' | oc apply -f -"
echo "apiVersion: multicluster.openshift.io/v1"
echo "kind: MultiClusterEngine"
echo "metadata:"
echo "  name: multiclusterengine"
echo "spec:"
echo "  availabilityConfig: Basic"
echo "  targetNamespace: multicluster-engine"
echo "EOF"