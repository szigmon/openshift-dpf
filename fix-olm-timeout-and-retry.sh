#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Fixing OLM Bundle Timeout and Retrying MCE ==="
echo ""

# Step 1: Delete the failed subscription to clear the state
echo "1. Cleaning up failed subscription..."
oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found

# Step 2: Check and clean up any failed bundle jobs
echo ""
echo "2. Cleaning up failed bundle unpacking jobs..."
for job in $(oc get jobs -n openshift-marketplace -o name | grep bundle); do
    echo "   Deleting $job"
    oc delete $job -n openshift-marketplace --ignore-not-found
done

for job in $(oc get jobs -n openshift-operator-lifecycle-manager -o name | grep bundle); do
    echo "   Deleting $job"
    oc delete $job -n openshift-operator-lifecycle-manager --ignore-not-found
done

# Step 3: Configure OLM for longer timeout
echo ""
echo "3. Configuring OLM for extended bundle timeout..."
cat > /tmp/olm-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: olm-config
  namespace: openshift-operator-lifecycle-manager
data:
  features: |
    {
      "bundleUnpackTimeout": "30m"
    }
EOF

# Apply or update the config
if oc get configmap olm-config -n openshift-operator-lifecycle-manager &>/dev/null; then
    echo "   Updating existing OLM config..."
    oc delete configmap olm-config -n openshift-operator-lifecycle-manager
fi
oc apply -f /tmp/olm-config.yaml

# Step 4: Restart OLM operators to pick up new config
echo ""
echo "4. Restarting OLM operators..."
oc delete pods -n openshift-operator-lifecycle-manager -l app=olm-operator
oc delete pods -n openshift-operator-lifecycle-manager -l app=catalog-operator

# Wait for OLM to be ready
echo "   Waiting for OLM to restart..."
sleep 20
wait_for_pods "openshift-operator-lifecycle-manager" "app=olm-operator" "status.phase=Running" "1/1" 30 5
wait_for_pods "openshift-operator-lifecycle-manager" "app=catalog-operator" "status.phase=Running" "1/1" 30 5

# Step 5: Alternative approach - try a different channel or version
echo ""
echo "5. Checking available MCE versions..."
echo "   Available channels:"
oc get packagemanifest multicluster-engine -o json | jq -r '.status.channels[].name' | sort -u

echo ""
echo "   Latest version in stable-2.8:"
oc get packagemanifest multicluster-engine -o json | jq -r '.status.channels[] | select(.name=="stable-2.8") | .currentCSV'

# Step 6: Create subscription with extended timeout in spec
echo ""
echo "6. Creating MCE subscription with extended config..."
cat > /tmp/mce-subscription-timeout.yaml << 'EOF'
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
  config:
    env:
    - name: BUNDLE_UNPACK_TIMEOUT
      value: "30m"
    - name: JOB_TIMEOUT
      value: "1800"
EOF

oc apply -f /tmp/mce-subscription-timeout.yaml

# Step 7: Monitor the installation
echo ""
echo "7. Monitoring installation (extended timeout applied)..."
echo "   This may take up to 30 minutes for bundle unpacking"
echo ""

# Monitor for 35 minutes
start_time=$(date +%s)
max_wait=2100  # 35 minutes

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt $max_wait ]; then
        echo ""
        echo "Timeout after 35 minutes"
        break
    fi
    
    # Check for InstallPlan
    INSTALLPLAN=$(oc get installplan -n multicluster-engine -o name 2>/dev/null | head -1)
    if [ -n "$INSTALLPLAN" ]; then
        PHASE=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Complete" ]; then
            echo ""
            echo "   ✓ InstallPlan completed!"
            break
        elif [ "$PHASE" = "Failed" ]; then
            echo ""
            echo "   ✗ InstallPlan failed"
            oc get $INSTALLPLAN -n multicluster-engine -o yaml | grep -A 10 "message:"
            break
        fi
    fi
    
    # Check subscription status every minute
    if [ $((elapsed % 60)) -eq 0 ]; then
        STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
        BUNDLE_FAILED=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="BundleUnpackFailed")].status}' 2>/dev/null || echo "")
        
        echo "   Progress at $((elapsed / 60)) minutes:"
        echo "     Subscription state: $STATE"
        if [ "$BUNDLE_FAILED" = "True" ]; then
            echo "     Bundle unpacking status: In progress (OLM will retry)"
        fi
        
        # Check for bundle jobs
        BUNDLE_JOBS=$(oc get jobs -n openshift-marketplace -o name | grep -c bundle || echo "0")
        if [ "$BUNDLE_JOBS" -gt 0 ]; then
            echo "     Active bundle jobs: $BUNDLE_JOBS"
        fi
    fi
    
    sleep 10
done

echo ""
echo "Final status:"
oc get subscription,installplan,csv -n multicluster-engine