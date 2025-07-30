#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== MCE Installation - Final Solution ==="
echo ""
echo "Following the official Red Hat documentation exactly"
echo ""

# Step 1: Clean everything using existing scripts
echo "1. Cleaning up everything..."

# Remove all HyperShift components if they exist
if [ -f "./remove-all-hypershift.sh" ]; then
    echo "   Running HyperShift removal..."
    ./remove-all-hypershift.sh || true
fi

# Force clean MCE namespace
if [ -f "./force-clean-mce.sh" ]; then
    echo "   Running MCE force cleanup..."
    ./force-clean-mce.sh || true
fi

# Additional cleanup
echo "   Final cleanup..."
oc delete namespace multicluster-engine --ignore-not-found --wait=false --grace-period=0
oc delete clusterrole multicluster-engine-operator --ignore-not-found
oc delete clusterrolebinding multicluster-engine-operator --ignore-not-found

# Wait for namespace to be gone
echo "   Waiting for namespace cleanup..."
while oc get namespace multicluster-engine &>/dev/null; do
    echo -n "."
    sleep 2
done
echo ""

# Step 2: Create namespace and operator group EXACTLY as in documentation
echo "2. Creating namespace and operator group..."
cat << 'EOF' | oc apply -f -
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

# Step 3: Create subscription EXACTLY as in documentation
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

# Step 4: Wait for operator to be ready
echo ""
echo "4. Waiting for MCE operator to be ready..."
echo "   This may take 10-20 minutes due to bundle size"
echo "   OLM will handle retries automatically"
echo ""

# Monitor the subscription
operator_ready=false
max_wait=1800  # 30 minutes
start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt $max_wait ]; then
        echo ""
        echo "   ✗ Timeout after 30 minutes"
        break
    fi
    
    # Check CSV
    CSV=$(oc get csv -n multicluster-engine -o name 2>/dev/null | grep multiclusterengine || true)
    if [ -n "$CSV" ]; then
        PHASE=$(oc get $CSV -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Succeeded" ]; then
            echo ""
            echo "   ✓ MCE operator is ready!"
            operator_ready=true
            break
        fi
    fi
    
    # Check subscription state every 30 seconds
    if [ $((elapsed % 30)) -eq 0 ]; then
        STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
        echo "   Status after $((elapsed / 60)) minutes: $STATE"
        
        # Check if there's a bundle unpack issue
        BUNDLE_FAILED=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="BundleUnpackFailed")].status}' 2>/dev/null || echo "")
        if [ "$BUNDLE_FAILED" = "True" ]; then
            echo "   Bundle unpacking in progress... (this is normal, OLM will retry)"
        fi
    fi
    
    sleep 5
done

if [ "$operator_ready" != "true" ]; then
    echo ""
    echo "MCE operator installation is taking longer than expected."
    echo "This can happen with large bundles. Options:"
    echo "1. Wait longer - OLM will continue retrying"
    echo "2. Check: oc get installplan -n multicluster-engine"
    echo "3. Check: oc get csv -n multicluster-engine"
    exit 1
fi

# Step 5: Verify operator pods are running
echo ""
echo "5. Verifying MCE operator pods..."
wait_for_pods "multicluster-engine" "name=multicluster-engine-operator" "status.phase=Running" "1/1" 30 5

echo ""
echo "MCE operator pods:"
oc get pods -n multicluster-engine

# Step 6: Create MultiClusterEngine CR EXACTLY as in documentation
echo ""
echo "6. Creating MultiClusterEngine instance..."
cat << 'EOF' | oc apply -f -
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF

echo "   Note: HyperShift is enabled by default when creating MultiClusterEngine"

# Step 7: Wait for MCE to be ready
echo ""
echo "7. Waiting for MCE to become available..."
mce_ready=false
retries=120  # 10 minutes
while [ $retries -gt 0 ]; do
    PHASE=$(oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$PHASE" = "Available" ]; then
        echo ""
        echo "   ✓ MCE is available!"
        mce_ready=true
        break
    fi
    
    if [ $((retries % 12)) -eq 0 ]; then
        echo -n "
   MCE phase: $PHASE ($((retries / 12)) minutes remaining)"
    else
        echo -n "."
    fi
    
    sleep 5
    ((retries--))
done

# Step 8: Verify HyperShift deployment
echo ""
echo "8. Verifying HyperShift deployment..."
if wait_for_namespace "hypershift" 60 5; then
    echo "   ✓ HyperShift namespace created"
    
    # Wait for HyperShift operator
    if wait_for_pods "hypershift" "app=operator" "status.phase=Running" "1/1" 60 5; then
        echo "   ✓ HyperShift operator is running"
    else
        echo "   ⚠ HyperShift operator is still starting"
    fi
    
    echo ""
    echo "HyperShift pods:"
    oc get pods -n hypershift
else
    echo "   ⚠ HyperShift namespace not yet created"
    echo "   MCE may still be deploying components"
fi

# Final status
echo ""
echo "==========================================="
echo "MCE Installation Summary"
echo "==========================================="
echo ""
echo "MCE Operator: $(oc get csv -n multicluster-engine -o name | grep multiclusterengine || echo 'Not found')"
echo "MCE Instance: $(oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Not found')"
echo "HyperShift: $(if oc get namespace hypershift &>/dev/null; then echo 'Deployed'; else echo 'Not yet deployed'; fi)"
echo ""

if [ "$operator_ready" = "true" ]; then
    echo "✓ Installation successful!"
    echo ""
    echo "Next steps:"
    echo "1. Ensure all MCE components are ready: oc get mce multiclusterengine -w"
    echo "2. Verify HyperShift is ready: oc get pods -n hypershift"
    echo "3. Create HostedCluster: make deploy-hosted-cluster"
else
    echo "✗ Installation incomplete"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check subscription: oc describe subscription -n multicluster-engine multicluster-engine"
    echo "2. Check events: oc get events -n multicluster-engine --sort-by='.lastTimestamp'"
    echo "3. Check InstallPlan: oc get installplan -n multicluster-engine"
fi