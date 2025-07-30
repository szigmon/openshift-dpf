#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Alternative MCE Installation Approach ==="
echo ""
echo "Since bundle unpacking keeps failing, let's try a different approach"
echo ""

# Option 1: Try stable-2.7 channel which might have a smaller bundle
echo "Option 1: Try MCE stable-2.7 channel (might have smaller bundle)"
echo "========================================================"
echo ""
echo "Would you like to try stable-2.7 instead of stable-2.8? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Cleaning up current subscription..."
    oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found
    
    echo "Creating subscription for stable-2.7..."
    cat << 'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: stable-2.7
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    
    echo ""
    echo "Monitor with: oc get subscription,installplan,csv -n multicluster-engine"
    echo "This uses official Red Hat MCE, just an earlier version"
    exit 0
fi

# Option 2: Check if the issue is with the specific registry
echo ""
echo "Option 2: Debug Registry Access"
echo "================================"
echo ""
echo "Checking if we can access Red Hat registry directly..."

# Test registry access
echo "Testing registry.redhat.io connectivity..."
oc run test-registry --image=registry.redhat.io/ubi8/ubi-minimal:latest --command -- sleep 30 --restart=Never 2>/dev/null || true
sleep 5
POD_STATUS=$(oc get pod test-registry -o jsonpath='{.status.phase}' 2>/dev/null || echo "Failed")
echo "Test pod status: $POD_STATUS"
oc delete pod test-registry --force --grace-period=0 2>/dev/null || true

if [ "$POD_STATUS" != "Running" ] && [ "$POD_STATUS" != "Succeeded" ]; then
    echo ""
    echo "Registry access issue detected!"
    echo "This might be why bundle unpacking fails"
    echo ""
    echo "Possible solutions:"
    echo "1. Check cluster's pull secret: oc get secret/pull-secret -n openshift-config"
    echo "2. Check proxy settings: oc get proxy cluster -o yaml"
    echo "3. Check if firewall is blocking registry.redhat.io"
fi

# Option 3: Try manual InstallPlan creation
echo ""
echo "Option 3: Force InstallPlan Creation"
echo "===================================="
echo ""
echo "Sometimes OLM gets stuck. Let's try to force progress..."
echo ""
echo "Would you like to try forcing an InstallPlan? (y/n)"
read -r response2

if [[ "$response2" =~ ^[Yy]$ ]]; then
    # Get the package details
    echo "Getting MCE package details..."
    CSV_NAME=$(oc get packagemanifest multicluster-engine -o json | jq -r '.status.channels[] | select(.name=="stable-2.8") | .currentCSV')
    echo "Target CSV: $CSV_NAME"
    
    # Create a manual InstallPlan
    cat > /tmp/manual-installplan.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: InstallPlan
metadata:
  generateName: multicluster-engine-manual-
  namespace: multicluster-engine
spec:
  approved: true
  approval: Manual
  clusterServiceVersionNames:
  - $CSV_NAME
  generation: 1
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    
    echo "Creating manual InstallPlan..."
    oc create -f /tmp/manual-installplan.yaml
    
    echo ""
    echo "Monitor with: oc get installplan -n multicluster-engine"
    exit 0
fi

# Option 4: Direct HyperShift without MCE
echo ""
echo "Option 4: Install HyperShift Directly (without MCE)"
echo "==================================================="
echo ""
echo "Since MCE bundle keeps failing, we can install HyperShift directly"
echo "This gives you the same hosted cluster functionality"
echo ""
echo "Would you like to install HyperShift directly? (y/n)"
read -r response3

if [[ "$response3" =~ ^[Yy]$ ]]; then
    echo "Running direct HyperShift installation..."
    if [ -f "./install-hypershift-direct.sh" ]; then
        ./install-hypershift-direct.sh
    else
        echo "Creating HyperShift namespace and installing operator..."
        hypershift install --hypershift-image=quay.io/hypershift/hypershift-operator:latest
    fi
    exit 0
fi

echo ""
echo "No option selected. Current status:"
oc get subscription,installplan,csv -n multicluster-engine