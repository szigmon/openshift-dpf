#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Clean MCE Installation (Based on Official Docs) ==="
echo ""

# Step 1: Clean up any existing resources
echo "1. Cleaning up any existing MCE/HyperShift resources..."

# Delete MCE CR first if exists
if oc get mce multiclusterengine &>/dev/null; then
    echo "   Deleting existing MCE instance..."
    oc delete mce multiclusterengine --wait=false
    sleep 10
fi

# Delete subscription
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    echo "   Deleting existing subscription..."
    oc delete subscription -n multicluster-engine multicluster-engine
    sleep 5
fi

# Step 2: Create MCE operator subscription
echo ""
echo "2. Creating MCE operator subscription..."
cat > /tmp/mce-operator-clean.yaml << 'EOF'
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
---
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

oc apply -f /tmp/mce-operator-clean.yaml

# Step 3: Wait for operator to be ready
echo ""
echo "3. Waiting for MCE operator to be ready..."
echo "   This may take up to 20 minutes due to bundle size..."

# Monitor subscription
subscription_ready=false
retries=240  # 20 minutes
while [ $retries -gt 0 ]; do
    STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "")
    
    # Check for CSV
    CSV=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
    
    if [ -n "$CSV" ] && [ "$CSV" != "null" ]; then
        # Check CSV status
        CSV_PHASE=$(oc get csv -n multicluster-engine "$CSV" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$CSV_PHASE" = "Succeeded" ]; then
            echo ""
            echo "   ✓ MCE operator is ready!"
            subscription_ready=true
            break
        fi
    fi
    
    # Check for bundle unpack failure
    BUNDLE_FAILED=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="BundleUnpackFailed")].status}' 2>/dev/null || echo "")
    if [ "$BUNDLE_FAILED" = "True" ]; then
        echo ""
        echo "   ✗ Bundle unpacking failed!"
        echo "   This is a known issue with MCE 2.8 bundle size."
        echo "   Try: ./install-mce-manual-csv.sh instead"
        exit 1
    fi
    
    # Progress indicator every 30 seconds
    if [ $((retries % 6)) -eq 0 ]; then
        echo -n "
   Still waiting... ($((retries / 12)) minutes remaining) State: $STATE"
    else
        echo -n "."
    fi
    
    sleep 5
    ((retries--))
done

if [ "$subscription_ready" != "true" ]; then
    echo ""
    echo "   ✗ Timeout waiting for MCE operator"
    echo "   Check status with: ./check-mce-subscription.sh"
    exit 1
fi

# Step 4: Create MultiClusterEngine instance
echo ""
echo "4. Creating MultiClusterEngine instance..."
echo "   Note: HyperShift is enabled by default in MCE"

cat > /tmp/mce-instance.yaml << 'EOF'
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF

oc apply -f /tmp/mce-instance.yaml

# Step 5: Wait for MCE to be ready
echo ""
echo "5. Waiting for MCE components to be ready..."
mce_retries=60
while [ $mce_retries -gt 0 ]; do
    # Check MCE status
    MCE_PHASE=$(oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$MCE_PHASE" = "Available" ]; then
        echo "   ✓ MCE is available!"
        break
    fi
    echo -n "."
    sleep 5
    ((mce_retries--))
done

# Step 6: Verify HyperShift deployment
echo ""
echo "6. Verifying HyperShift deployment..."
hs_retries=60
while [ $hs_retries -gt 0 ]; do
    if oc get namespace hypershift &>/dev/null; then
        # Check for operator pods
        OPERATOR_READY=$(oc get pods -n hypershift -l app=operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
        if [ "$OPERATOR_READY" = "Running" ]; then
            echo "   ✓ HyperShift operator is running!"
            break
        fi
    fi
    echo -n "."
    sleep 5
    ((hs_retries--))
done

# Final verification
echo ""
echo "7. Final Status:"
echo ""
echo "MCE Status:"
oc get mce multiclusterengine -o wide || echo "MCE not found"

echo ""
echo "HyperShift Namespace:"
oc get namespace hypershift || echo "HyperShift namespace not found"

echo ""
echo "HyperShift Pods:"
oc get pods -n hypershift || echo "No pods found"

echo ""
echo "✓ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Verify HyperShift is ready: oc get pods -n hypershift"
echo "2. Create HostedCluster: make deploy-hosted-cluster"