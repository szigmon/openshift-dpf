#!/bin/bash

set -euo pipefail

echo "=== Manual MCE Installation Workaround ==="
echo ""

# First, let's try to find the exact bundle image
echo "1. Finding MCE bundle image..."
BUNDLE_IMAGE=$(oc get packagemanifest multicluster-engine -o json | jq -r '.status.channels[] | select(.name=="stable-2.8") | .currentCSVDesc.annotations."operatorframework.io/bundle-image"' 2>/dev/null)

if [ -z "$BUNDLE_IMAGE" ]; then
    echo "Could not find bundle image from packagemanifest. Trying alternative method..."
    # Try to get it from the catalog
    BUNDLE_IMAGE="registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator:v2.8.2"
fi

echo "Bundle image: $BUNDLE_IMAGE"

# Option 1: Try to increase OLM timeout
echo ""
echo "2. Checking OLM configuration..."
oc get configmap -n openshift-operator-lifecycle-manager olm-config -o yaml 2>/dev/null || echo "No OLM config found"

# Option 2: Create InstallPlan manually
echo ""
echo "3. Creating manual InstallPlan..."
cat > /tmp/mce-installplan.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: InstallPlan
metadata:
  generateName: multicluster-engine-
  namespace: multicluster-engine
spec:
  approved: true
  approval: Automatic
  clusterServiceVersionNames:
  - multicluster-engine.v2.8.2
  generation: 1
EOF

# Option 3: Direct CSV installation
echo ""
echo "4. Alternative: Direct installation approach"
echo "   This requires extracting the CSV from the bundle"
echo ""
echo "Would you like to:"
echo "1) Try creating manual InstallPlan"
echo "2) Extract and apply CSV directly (more complex)"
echo "3) Wait longer for bundle unpacking"
echo ""
echo "For now, let's check if there's a proxy or network issue..."

# Check for proxy settings
echo ""
echo "5. Checking proxy configuration..."
oc get proxy cluster -o yaml | grep -E "httpProxy|httpsProxy|noProxy" || echo "No proxy configured"

# Check if we can reach the registry
echo ""
echo "6. Testing registry connectivity..."
oc run test-pull --image=registry.redhat.io/ubi8/ubi-minimal:latest --command -- sleep 30 2>/dev/null || true
sleep 5
oc get pod test-pull -o jsonpath='{.status.phase}' 2>/dev/null || echo "Could not test registry pull"
oc delete pod test-pull --force --grace-period=0 2>/dev/null || true