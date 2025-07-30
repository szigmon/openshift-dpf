#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Installing MCE with Timeout Workaround ==="
echo ""

# Step 1: Increase OLM bundle unpacking timeout
echo "1. Configuring OLM for extended bundle unpacking timeout..."
cat > /tmp/olm-config-patch.yaml << 'EOF'
data:
  features: |
    {
      "bundleUnpackTimeout": "20m"
    }
EOF

# Apply the OLM config patch
if oc get configmap -n openshift-operator-lifecycle-manager olm-config &>/dev/null; then
    echo "   Patching existing OLM config..."
    oc patch configmap -n openshift-operator-lifecycle-manager olm-config --type merge --patch-file /tmp/olm-config-patch.yaml
else
    echo "   Creating OLM config with extended timeout..."
    cat > /tmp/olm-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: olm-config
  namespace: openshift-operator-lifecycle-manager
data:
  features: |
    {
      "bundleUnpackTimeout": "20m"
    }
EOF
    oc apply -f /tmp/olm-config.yaml
fi

# Restart OLM pods to pick up the new configuration
echo "   Restarting OLM pods to apply timeout configuration..."
oc delete pods -n openshift-operator-lifecycle-manager -l app=olm-operator
oc delete pods -n openshift-operator-lifecycle-manager -l app=catalog-operator

# Wait for OLM to be ready again
echo "   Waiting for OLM to restart..."
sleep 30
wait_for_pods "openshift-operator-lifecycle-manager" "app=olm-operator" "status.phase=Running" "1/1" 30 5
wait_for_pods "openshift-operator-lifecycle-manager" "app=catalog-operator" "status.phase=Running" "1/1" 30 5

# Step 2: Clean up any stuck resources
echo ""
echo "2. Cleaning up any stuck MCE resources..."
# Delete stuck subscription if exists
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    echo "   Removing existing MCE subscription..."
    oc delete subscription -n multicluster-engine multicluster-engine --wait=false
fi

# Delete namespace if exists and recreate
if oc get namespace multicluster-engine &>/dev/null; then
    echo "   Cleaning up multicluster-engine namespace..."
    oc delete namespace multicluster-engine --wait=false --grace-period=0
    # Wait for deletion
    retries=30
    while [ $retries -gt 0 ]; do
        if ! oc get namespace multicluster-engine &>/dev/null; then
            break
        fi
        echo -n "."
        sleep 2
        ((retries--))
    done
fi

# Step 3: Install MCE with the extended timeout
echo ""
echo "3. Installing MCE operator..."
oc apply -f manifests/cluster-installation/mce-operator.yaml

# Step 4: Monitor the installation
echo ""
echo "4. Monitoring MCE installation (this may take up to 20 minutes)..."
echo "   Checking for InstallPlan creation..."

install_retries=120  # 20 minutes with 10 second intervals
installplan_found=false

while [ $install_retries -gt 0 ]; do
    # Check if InstallPlan exists
    if oc get installplan -n multicluster-engine -o name 2>/dev/null | grep -q "installplan"; then
        installplan_found=true
        echo ""
        echo "   ✓ InstallPlan created!"
        INSTALLPLAN=$(oc get installplan -n multicluster-engine -o name | head -1)
        echo "   InstallPlan: $INSTALLPLAN"
        
        # Check InstallPlan status
        PHASE=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "   Phase: $PHASE"
        
        if [ "$PHASE" = "Complete" ]; then
            echo "   ✓ InstallPlan completed successfully!"
            break
        elif [ "$PHASE" = "Failed" ]; then
            echo "   ✗ InstallPlan failed!"
            oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="Installed")].message}' 2>/dev/null
            exit 1
        fi
    else
        echo -n "."
    fi
    
    sleep 10
    ((install_retries--))
    
    # Every minute, show status
    if [ $((install_retries % 6)) -eq 0 ] && [ $install_retries -gt 0 ]; then
        echo ""
        echo "   Still waiting... ($((install_retries / 6)) minutes remaining)"
        # Check subscription status
        oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="CatalogSourcesUnhealthy")].message}' 2>/dev/null || true
    fi
done

if [ $install_retries -eq 0 ]; then
    echo ""
    echo "   ✗ Timeout waiting for MCE installation"
    echo "   Checking subscription status..."
    oc get subscription -n multicluster-engine multicluster-engine -o yaml
    exit 1
fi

# Step 5: Wait for CSV to be ready
echo ""
echo "5. Waiting for MCE operator to be ready..."
csv_retries=60
while [ $csv_retries -gt 0 ]; do
    if oc get csv -n multicluster-engine | grep -q "multiclusterengine.*Succeeded"; then
        echo "   ✓ MCE operator is ready!"
        break
    fi
    echo -n "."
    sleep 5
    ((csv_retries--))
done

if [ $csv_retries -eq 0 ]; then
    echo "   ✗ Timeout waiting for CSV"
    exit 1
fi

# Step 6: Apply MCE configuration to enable HyperShift
echo ""
echo "6. Enabling HyperShift in MCE..."
oc apply -f manifests/cluster-installation/mce-hypershift-config.yaml

# Step 7: Verify HyperShift is deployed
echo ""
echo "7. Verifying HyperShift deployment..."
hypershift_retries=60
while [ $hypershift_retries -gt 0 ]; do
    if oc get deployment -n hypershift hypershift-operator &>/dev/null || oc get deployment -n hypershift operator &>/dev/null; then
        echo "   ✓ HyperShift operator deployed!"
        break
    fi
    echo -n "."
    sleep 5
    ((hypershift_retries--))
done

if [ $hypershift_retries -eq 0 ]; then
    echo "   ✗ Timeout waiting for HyperShift deployment"
    exit 1
fi

echo ""
echo "✓ MCE installed successfully with HyperShift enabled!"
echo ""
echo "Next steps:"
echo "1. Verify MCE status: oc get mce -n multicluster-engine"
echo "2. Check HyperShift: oc get pods -n hypershift"
echo "3. Create HostedCluster: make deploy-hosted-cluster"