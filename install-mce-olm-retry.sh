#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== MCE Installation via OLM (Retry with Fixes) ==="
echo ""

# Step 1: Clean up manual attempts
echo "1. Cleaning up manual installation attempts..."

# Delete manual deployment
oc delete deployment -n multicluster-engine multicluster-engine-operator --ignore-not-found

# Delete manual CSV
oc delete csv -n multicluster-engine multicluster-engine.v2.8.2 --ignore-not-found

# Delete manual RBAC
oc delete clusterrole multicluster-engine-operator --ignore-not-found
oc delete clusterrolebinding multicluster-engine-operator --ignore-not-found
oc delete serviceaccount -n multicluster-engine multicluster-engine-operator --ignore-not-found

# Delete any failed InstallPlans
for ip in $(oc get installplan -n multicluster-engine -o name 2>/dev/null); do
    oc delete $ip -n multicluster-engine --ignore-not-found
done

# Step 2: Ensure namespace and operator group exist
echo ""
echo "2. Ensuring namespace and operator group..."
cat > /tmp/mce-namespace-og.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: multicluster-engine
  labels:
    openshift.io/cluster-monitoring: "true"
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

oc apply -f /tmp/mce-namespace-og.yaml

# Step 3: Check if subscription exists and delete if failed
echo ""
echo "3. Checking existing subscription..."
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "")
    BUNDLE_FAILED=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="BundleUnpackFailed")].status}' 2>/dev/null || echo "")
    
    if [ "$BUNDLE_FAILED" = "True" ] || [ -z "$STATE" ]; then
        echo "   Removing failed subscription..."
        oc delete subscription -n multicluster-engine multicluster-engine
        sleep 10
    else
        echo "   Subscription exists in state: $STATE"
    fi
fi

# Step 4: Create subscription with installPlanApproval Manual to control timing
echo ""
echo "4. Creating MCE subscription with manual approval..."
cat > /tmp/mce-subscription.yaml << 'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: stable-2.8
  installPlanApproval: Manual
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  config:
    env:
    - name: BUNDLE_UNPACK_TIMEOUT
      value: "20m"
EOF

oc apply -f /tmp/mce-subscription.yaml

# Step 5: Wait for InstallPlan to be created
echo ""
echo "5. Waiting for InstallPlan to be created..."
installplan_found=false
retries=60
while [ $retries -gt 0 ]; do
    INSTALLPLAN=$(oc get installplan -n multicluster-engine -o name 2>/dev/null | grep -v "multicluster-engine.v" | head -1)
    if [ -n "$INSTALLPLAN" ]; then
        echo ""
        echo "   ✓ InstallPlan created: $INSTALLPLAN"
        installplan_found=true
        break
    fi
    echo -n "."
    sleep 2
    ((retries--))
done

if [ "$installplan_found" != "true" ]; then
    echo ""
    echo "   ✗ No InstallPlan created"
    echo "   Checking subscription status..."
    oc get subscription -n multicluster-engine multicluster-engine -o yaml | grep -A 10 "status:"
    exit 1
fi

# Step 6: Approve the InstallPlan
echo ""
echo "6. Approving InstallPlan..."
oc patch $INSTALLPLAN -n multicluster-engine --type merge -p '{"spec":{"approved":true}}'

# Step 7: Monitor InstallPlan progress
echo ""
echo "7. Monitoring InstallPlan progress (this may take up to 20 minutes)..."
plan_complete=false
retries=240  # 20 minutes with 5 second intervals
while [ $retries -gt 0 ]; do
    PHASE=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    
    if [ "$PHASE" = "Complete" ]; then
        echo ""
        echo "   ✓ InstallPlan completed successfully!"
        plan_complete=true
        break
    elif [ "$PHASE" = "Failed" ]; then
        echo ""
        echo "   ✗ InstallPlan failed!"
        echo "   Checking failure reason..."
        oc get $INSTALLPLAN -n multicluster-engine -o yaml | grep -A 20 "conditions:"
        exit 1
    fi
    
    # Show progress every 30 seconds
    if [ $((retries % 6)) -eq 0 ]; then
        echo -n "
   Still waiting... Phase: $PHASE ($((retries / 12)) minutes remaining)"
        # Check bundle unpack status
        BUNDLE_LOOKUP=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.bundleLookups[0].conditions[0].type}' 2>/dev/null || echo "")
        if [ -n "$BUNDLE_LOOKUP" ]; then
            echo -n " Bundle: $BUNDLE_LOOKUP"
        fi
    else
        echo -n "."
    fi
    
    sleep 5
    ((retries--))
done

if [ "$plan_complete" != "true" ]; then
    echo ""
    echo "   ✗ Timeout waiting for InstallPlan"
    echo "   Current status:"
    oc get $INSTALLPLAN -n multicluster-engine -o yaml | grep -A 10 "status:"
    exit 1
fi

# Step 8: Wait for CSV to be ready
echo ""
echo "8. Waiting for MCE CSV to be ready..."
csv_ready=false
retries=60
while [ $retries -gt 0 ]; do
    CSV=$(oc get csv -n multicluster-engine -o name 2>/dev/null | grep multiclusterengine | head -1)
    if [ -n "$CSV" ]; then
        PHASE=$(oc get $CSV -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Succeeded" ]; then
            echo "   ✓ MCE operator is ready!"
            csv_ready=true
            break
        fi
    fi
    echo -n "."
    sleep 5
    ((retries--))
done

if [ "$csv_ready" != "true" ]; then
    echo ""
    echo "   ✗ CSV not ready"
    exit 1
fi

# Step 9: Create MultiClusterEngine instance
echo ""
echo "9. Creating MultiClusterEngine instance..."
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

# Step 10: Wait for MCE to be ready
echo ""
echo "10. Waiting for MCE to be ready..."
wait_for_mce_ready() {
    local retries=60
    while [ $retries -gt 0 ]; do
        PHASE=$(oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Available" ]; then
            return 0
        fi
        echo -n "."
        sleep 5
        ((retries--))
    done
    return 1
}

if wait_for_mce_ready; then
    echo ""
    echo "   ✓ MCE is available!"
else
    echo ""
    echo "   MCE is taking time to become ready"
fi

# Step 11: Check HyperShift deployment
echo ""
echo "11. Checking HyperShift deployment..."
if oc get namespace hypershift &>/dev/null; then
    echo "   ✓ HyperShift namespace exists"
    echo "   HyperShift pods:"
    oc get pods -n hypershift
else
    echo "   HyperShift namespace not yet created"
fi

echo ""
echo "✓ MCE installation via OLM completed!"
echo ""
echo "Next steps:"
echo "1. Monitor MCE status: oc get mce multiclusterengine -w"
echo "2. Check HyperShift: oc get pods -n hypershift"
echo "3. Once ready, create HostedCluster: make deploy-hosted-cluster"