#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Simple MCE Installation ==="
echo ""

# Step 1: Clean up any existing MCE resources
echo "1. Cleaning up any existing MCE resources..."
if oc get namespace multicluster-engine &>/dev/null; then
    echo "   Found existing MCE namespace, cleaning up..."
    
    # Delete subscription
    if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
        oc delete subscription -n multicluster-engine multicluster-engine --wait=false
    fi
    
    # Delete CSV
    for csv in $(oc get csv -n multicluster-engine -o name | grep multiclusterengine); do
        oc delete $csv -n multicluster-engine --wait=false
    done
    
    # Delete MCE CR if exists
    if oc get mce -n multicluster-engine &>/dev/null; then
        oc delete mce --all -n multicluster-engine --wait=false
    fi
    
    # Delete namespace
    oc delete namespace multicluster-engine --wait=false --grace-period=0
    sleep 10
fi

# Step 2: Install MCE operator
echo ""
echo "2. Installing MCE operator..."
oc apply -f manifests/cluster-installation/mce-operator.yaml

# Step 3: Wait for subscription to be ready
echo ""
echo "3. Waiting for MCE subscription..."
retries=30
while [ $retries -gt 0 ]; do
    STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "")
    if [ "$STATE" = "AtLatestKnown" ] || [ "$STATE" = "UpgradeAvailable" ]; then
        echo "   ✓ Subscription ready (state: $STATE)"
        break
    fi
    echo -n "."
    sleep 5
    ((retries--))
done

# Step 4: Check for InstallPlan
echo ""
echo "4. Checking for InstallPlan..."
sleep 10
INSTALLPLAN=$(oc get installplan -n multicluster-engine -o name 2>/dev/null | head -1)
if [ -n "$INSTALLPLAN" ]; then
    echo "   Found: $INSTALLPLAN"
    
    # Check if it needs approval
    APPROVED=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.spec.approved}' 2>/dev/null || echo "false")
    if [ "$APPROVED" != "true" ]; then
        echo "   Approving InstallPlan..."
        oc patch $INSTALLPLAN -n multicluster-engine --type merge -p '{"spec":{"approved":true}}'
    fi
    
    # Wait for InstallPlan to complete
    echo "   Waiting for InstallPlan to complete (this may take 10-20 minutes)..."
    plan_retries=240  # 20 minutes
    while [ $plan_retries -gt 0 ]; do
        PHASE=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Complete" ]; then
            echo ""
            echo "   ✓ InstallPlan completed!"
            break
        elif [ "$PHASE" = "Failed" ]; then
            echo ""
            echo "   ✗ InstallPlan failed!"
            # Get failure details
            echo "   Checking failure reason..."
            oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="Installed")]}' | jq .
            exit 1
        fi
        
        # Show progress every minute
        if [ $((plan_retries % 12)) -eq 0 ]; then
            echo ""
            echo "   Still waiting... Phase: $PHASE ($((plan_retries / 12)) minutes remaining)"
        else
            echo -n "."
        fi
        
        sleep 5
        ((plan_retries--))
    done
    
    if [ $plan_retries -eq 0 ]; then
        echo ""
        echo "   ✗ Timeout waiting for InstallPlan"
        echo "   Current phase: $PHASE"
        echo "   Try running: ./install-mce-manual-csv.sh"
        exit 1
    fi
else
    echo "   No InstallPlan created yet. The subscription may still be processing."
    echo "   Wait a few minutes and check: oc get installplan -n multicluster-engine"
    echo "   Or try: ./install-mce-manual-csv.sh for direct installation"
    exit 1
fi

# Step 5: Wait for CSV
echo ""
echo "5. Waiting for MCE operator CSV..."
csv_retries=60
while [ $csv_retries -gt 0 ]; do
    CSV=$(oc get csv -n multicluster-engine -o name 2>/dev/null | grep multiclusterengine | head -1)
    if [ -n "$CSV" ]; then
        PHASE=$(oc get $CSV -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Succeeded" ]; then
            echo "   ✓ MCE operator ready!"
            break
        fi
    fi
    echo -n "."
    sleep 5
    ((csv_retries--))
done

# Step 6: Enable HyperShift
echo ""
echo "6. Enabling HyperShift in MCE..."
oc apply -f manifests/cluster-installation/mce-hypershift-config.yaml

# Step 7: Wait for HyperShift
echo ""
echo "7. Waiting for HyperShift to be deployed by MCE..."
hypershift_retries=60
while [ $hypershift_retries -gt 0 ]; do
    if oc get namespace hypershift &>/dev/null; then
        if oc get deployment -n hypershift hypershift-operator &>/dev/null || oc get deployment -n hypershift operator &>/dev/null; then
            echo "   ✓ HyperShift deployed!"
            break
        fi
    fi
    echo -n "."
    sleep 5
    ((hypershift_retries--))
done

# Final status
echo ""
echo "8. Final Status:"
echo "   MCE:"
oc get mce -n multicluster-engine
echo ""
echo "   HyperShift:"
oc get pods -n hypershift 2>/dev/null || echo "   Namespace not yet created"

echo ""
echo "✓ MCE installation complete!"
echo ""
echo "You can now create the HostedCluster with: make deploy-hosted-cluster"