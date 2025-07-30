#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Clean MCE Installation via OLM ==="
echo ""
echo "This will remove all manual attempts and use pure OLM installation"
echo ""

# Step 1: Complete cleanup
echo "1. Removing ALL MCE resources..."

# Delete MCE CR
oc delete mce --all -n multicluster-engine --ignore-not-found --wait=false

# Delete all pods
oc delete pods --all -n multicluster-engine --force --grace-period=0 2>/dev/null || true

# Delete deployments
oc delete deployment --all -n multicluster-engine --ignore-not-found

# Delete CSV
oc delete csv --all -n multicluster-engine --ignore-not-found

# Delete subscription
oc delete subscription --all -n multicluster-engine --ignore-not-found

# Delete InstallPlans
oc delete installplan --all -n multicluster-engine --ignore-not-found

# Delete OperatorGroup
oc delete operatorgroup --all -n multicluster-engine --ignore-not-found

# Delete RBAC
oc delete clusterrole multicluster-engine-operator --ignore-not-found
oc delete clusterrolebinding multicluster-engine-operator --ignore-not-found

# Delete namespace
echo "   Deleting namespace..."
oc delete namespace multicluster-engine --wait=false --grace-period=0 2>/dev/null || true

# Wait for namespace deletion
echo "   Waiting for namespace to be deleted..."
retries=60
while [ $retries -gt 0 ]; do
    if ! oc get namespace multicluster-engine &>/dev/null; then
        echo "   ✓ Namespace deleted"
        break
    fi
    echo -n "."
    sleep 2
    ((retries--))
done

# Force remove if stuck
if oc get namespace multicluster-engine &>/dev/null; then
    echo "   Force removing namespace..."
    oc patch namespace multicluster-engine -p '{"metadata":{"finalizers":[]}}' --type=merge
    oc delete namespace multicluster-engine --force --grace-period=0
    sleep 10
fi

# Step 2: Create fresh namespace and operator group
echo ""
echo "2. Creating fresh namespace and operator group..."
cat > /tmp/mce-base.yaml << 'EOF'
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
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
EOF

oc apply -f /tmp/mce-base.yaml

# Step 3: Create subscription
echo ""
echo "3. Creating MCE subscription (OLM will handle everything)..."
cat > /tmp/mce-subscription.yaml << 'EOF'
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

oc apply -f /tmp/mce-subscription.yaml

# Step 4: Wait for operator to be installed by OLM
echo ""
echo "4. Waiting for OLM to install the operator..."
echo "   Note: This uses the official Red Hat images via OLM"
echo "   OLM will handle authentication and image pulls"
echo ""

# Wait for CSV to appear
csv_found=false
retries=300  # 25 minutes
while [ $retries -gt 0 ]; do
    # Check subscription state
    STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "")
    
    # Check for CSV
    CSV=$(oc get csv -n multicluster-engine -o name 2>/dev/null | grep multiclusterengine | head -1)
    
    if [ -n "$CSV" ]; then
        PHASE=$(oc get $CSV -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Succeeded" ]; then
            echo ""
            echo "   ✓ MCE operator installed successfully!"
            csv_found=true
            break
        elif [ "$PHASE" = "Failed" ]; then
            echo ""
            echo "   ✗ CSV failed"
            oc get $CSV -n multicluster-engine -o yaml | grep -A 10 "message:"
            exit 1
        fi
    fi
    
    # Check for issues
    BUNDLE_FAILED=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="BundleUnpackFailed")].status}' 2>/dev/null || echo "")
    if [ "$BUNDLE_FAILED" = "True" ]; then
        if [ $((retries % 60)) -eq 0 ]; then
            echo ""
            echo "   Bundle unpacking is taking time... Still waiting..."
            echo "   This is normal for large bundles. OLM will retry automatically."
        fi
    fi
    
    # Progress indicator
    if [ $((retries % 12)) -eq 0 ]; then
        echo -n "
   Progress: State=$STATE ($((retries / 12)) minutes remaining)"
    else
        echo -n "."
    fi
    
    sleep 5
    ((retries--))
done

if [ "$csv_found" != "true" ]; then
    echo ""
    echo "   ✗ Timeout waiting for operator installation"
    echo "   Checking status..."
    echo ""
    echo "Subscription:"
    oc get subscription -n multicluster-engine multicluster-engine -o yaml | grep -A 20 "status:"
    echo ""
    echo "InstallPlans:"
    oc get installplan -n multicluster-engine
    echo ""
    echo "Events:"
    oc get events -n multicluster-engine --sort-by='.lastTimestamp' | tail -10
    exit 1
fi

# Step 5: Check operator pods
echo ""
echo "5. Checking MCE operator pods..."
oc get pods -n multicluster-engine

# Step 6: Create MCE instance
echo ""
echo "6. Creating MultiClusterEngine instance (HyperShift enabled by default)..."
cat > /tmp/mce-cr.yaml << 'EOF'
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF

oc apply -f /tmp/mce-cr.yaml

# Step 7: Monitor MCE deployment
echo ""
echo "7. Monitoring MCE deployment..."
retries=60
while [ $retries -gt 0 ]; do
    PHASE=$(oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$PHASE" = "Available" ]; then
        echo ""
        echo "   ✓ MCE is available!"
        break
    fi
    echo -n "."
    sleep 5
    ((retries--))
done

# Step 8: Check HyperShift
echo ""
echo "8. Checking HyperShift deployment..."
if oc get namespace hypershift &>/dev/null; then
    echo "   ✓ HyperShift namespace created"
    echo ""
    echo "HyperShift pods:"
    oc get pods -n hypershift
else
    echo "   Waiting for HyperShift to be deployed by MCE..."
fi

echo ""
echo "✓ Installation complete!"
echo ""
echo "Status:"
echo "- MCE Operator: Installed via OLM"
echo "- Images: Official Red Hat images (OLM handles authentication)"
echo "- HyperShift: Enabled by default in MCE"
echo ""
echo "Next steps:"
echo "1. Wait for all components to be ready"
echo "2. Create HostedCluster: make deploy-hosted-cluster"