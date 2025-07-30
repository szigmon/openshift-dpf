#!/bin/bash

set -euo pipefail

echo "=== Fixing MCE Bundle Timeout Issue ==="
echo ""

# Step 1: Clean up failed resources
echo "1. Cleaning up failed MCE installation..."

# Delete failed installplans
echo "   Deleting failed InstallPlans..."
for ip in $(oc get installplan -n multicluster-engine -o name 2>/dev/null); do
    PHASE=$(oc get $ip -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$PHASE" = "Failed" ] || [ -z "$PHASE" ]; then
        echo "   Deleting $ip"
        oc delete $ip -n multicluster-engine --force --grace-period=0
    fi
done

# Delete subscription to force retry
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    echo "   Deleting MCE subscription..."
    oc delete subscription -n multicluster-engine multicluster-engine
    sleep 5
fi

# Step 2: Clean OLM cache
echo ""
echo "2. Cleaning OLM bundle cache..."
# Delete bundle unpacking jobs
echo "   Deleting bundle unpacking jobs..."
oc delete jobs -n openshift-marketplace -l olm.catalogSource 2>/dev/null || true
oc delete jobs -n openshift-operator-lifecycle-manager -l olm.catalogSource 2>/dev/null || true

# Step 3: Increase memory limits for OLM
echo ""
echo "3. Increasing OLM operator memory limits..."
for deployment in olm-operator catalog-operator; do
    if oc get deployment -n openshift-operator-lifecycle-manager $deployment &>/dev/null; then
        echo "   Patching $deployment..."
        oc patch deployment -n openshift-operator-lifecycle-manager $deployment --type=json -p='[
            {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "1Gi"},
            {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "512Mi"}
        ]' 2>/dev/null || echo "   Could not patch resources"
    fi
done

# Wait for OLM to restart
echo "   Waiting for OLM to restart..."
sleep 20

# Step 4: Create priority class for bundle jobs
echo ""
echo "4. Creating high priority class for bundle jobs..."
cat > /tmp/bundle-priority.yaml << 'EOF'
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: olm-bundle-high-priority
value: 1000
globalDefault: false
description: "High priority class for OLM bundle unpacking jobs"
EOF
oc apply -f /tmp/bundle-priority.yaml

# Step 5: Pre-warm the catalog
echo ""
echo "5. Pre-warming the catalog..."
echo "   Forcing catalog refresh..."
CATALOG_POD=$(oc get pods -n openshift-marketplace -l olm.catalogSource=redhat-operators -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CATALOG_POD" ]; then
    echo "   Restarting catalog pod: $CATALOG_POD"
    oc delete pod -n openshift-marketplace $CATALOG_POD --force --grace-period=0
    sleep 10
fi

# Step 6: Apply MCE with retry logic
echo ""
echo "6. Installing MCE with retry logic..."
echo "   Applying MCE operator manifests..."
oc apply -f manifests/cluster-installation/mce-operator.yaml

# Monitor with extended timeout
echo ""
echo "7. Monitoring installation (extended timeout)..."
MAX_WAIT=1800  # 30 minutes
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $MAX_WAIT ]; then
        echo "   Timeout after 30 minutes"
        break
    fi
    
    # Check for InstallPlan
    INSTALLPLAN=$(oc get installplan -n multicluster-engine -o name 2>/dev/null | head -1)
    if [ -n "$INSTALLPLAN" ]; then
        PHASE=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$PHASE" = "Complete" ]; then
            echo "   ✓ InstallPlan completed!"
            break
        elif [ "$PHASE" = "Failed" ]; then
            # Get failure reason
            echo "   InstallPlan failed. Checking reason..."
            REASON=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="Installed")].message}' 2>/dev/null || echo "Unknown")
            echo "   Reason: $REASON"
            
            if echo "$REASON" | grep -q "deadline"; then
                echo "   Bundle timeout detected. Creating manual workaround..."
                # Try manual approach
                ./install-mce-manual-csv.sh
                exit $?
            fi
        else
            echo -n "."
        fi
    else
        echo -n "."
    fi
    
    sleep 10
done

echo ""
echo "Done. Check status with:"
echo "  oc get subscription -n multicluster-engine multicluster-engine"
echo "  oc get installplan -n multicluster-engine"
echo "  oc get csv -n multicluster-engine"