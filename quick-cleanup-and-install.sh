#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Quick MCE Installation ==="
echo ""

# Step 1: Quick cleanup without waiting for stuck namespaces
echo "1. Quick cleanup..."

# Delete resources but don't wait for namespaces
oc delete deployment --all -n multicluster-engine --ignore-not-found &>/dev/null || true
oc delete pods --all -n multicluster-engine --force --grace-period=0 --ignore-not-found &>/dev/null || true
oc delete csv --all -n multicluster-engine --ignore-not-found &>/dev/null || true
oc delete subscription --all -n multicluster-engine --ignore-not-found &>/dev/null || true
oc delete installplan --all -n multicluster-engine --ignore-not-found &>/dev/null || true
oc delete operatorgroup --all -n multicluster-engine --ignore-not-found &>/dev/null || true

# Try to delete namespaces but don't wait
oc delete namespace multicluster-engine --wait=false --grace-period=0 &>/dev/null || true
oc delete namespace hypershift --wait=false --grace-period=0 &>/dev/null || true

# Remove finalizers if namespaces exist
oc patch namespace multicluster-engine -p '{"metadata":{"finalizers":[]}}' --type=merge &>/dev/null || true
oc patch namespace hypershift -p '{"metadata":{"finalizers":[]}}' --type=merge &>/dev/null || true

echo "   Cleanup initiated (not waiting for completion)"

# Step 2: Create MCE namespace (will fail if exists, that's ok)
echo ""
echo "2. Creating MCE namespace and operator group..."
cat << 'EOF' | oc apply -f - || true
apiVersion: v1
kind: Namespace
metadata:
  name: multicluster-engine
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine-operatorgroup
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
EOF

# Step 3: Create subscription
echo ""
echo "3. Creating MCE subscription..."
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

# Step 4: Monitor installation
echo ""
echo "4. Monitoring MCE installation..."
echo "   Note: Bundle unpacking may take 10-20 minutes"
echo ""

# Simple monitoring loop
operator_ready=false
for i in {1..360}; do  # 30 minutes max
    # Check CSV every 30 seconds
    if [ $((i % 6)) -eq 0 ]; then
        CSV=$(oc get csv -n multicluster-engine -o name 2>/dev/null | grep multiclusterengine || true)
        if [ -n "$CSV" ]; then
            PHASE=$(oc get $CSV -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$PHASE" = "Succeeded" ]; then
                echo ""
                echo "   ✓ MCE operator is ready!"
                operator_ready=true
                break
            else
                echo "   Progress: CSV phase = $PHASE ($(( i / 12 )) minutes elapsed)"
            fi
        else
            STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
            echo "   Progress: Subscription state = $STATE ($(( i / 12 )) minutes elapsed)"
        fi
    fi
    sleep 5
done

if [ "$operator_ready" != "true" ]; then
    echo ""
    echo "MCE operator not ready after 30 minutes."
    echo "Check: oc get csv -n multicluster-engine"
    echo "Check: oc get installplan -n multicluster-engine"
    exit 1
fi

# Step 5: Create MCE instance
echo ""
echo "5. Creating MultiClusterEngine instance..."
cat << 'EOF' | oc apply -f -
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF

echo ""
echo "✓ MCE installation initiated!"
echo ""
echo "Monitor with:"
echo "  oc get mce multiclusterengine -w"
echo "  oc get pods -n hypershift"