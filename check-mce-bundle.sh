#!/bin/bash

set -euo pipefail

echo "=== Checking MCE Bundle Information ==="
echo ""

# Method 1: Check packagemanifest
echo "1. Checking packagemanifest for MCE..."
oc get packagemanifest multicluster-engine -n openshift-marketplace -o json | jq '.status.channels[] | select(.name=="stable-2.8") | {channel: .name, csv: .currentCSV}'

# Method 2: Check available CSVs in catalog
echo ""
echo "2. Checking for MCE images in catalog..."
oc get packagemanifest multicluster-engine -n openshift-marketplace -o json | jq -r '.status.channels[] | select(.name=="stable-2.8") | .currentCSVDesc.relatedImages[]? | select(.name | contains("multicluster"))'

# Method 3: Direct catalog query
echo ""
echo "3. Querying catalog for MCE operator image..."
CATALOG_SOURCE="redhat-operators"
CATALOG_POD=$(oc get pods -n openshift-marketplace -l "olm.catalogSource=$CATALOG_SOURCE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$CATALOG_POD" ]; then
    echo "   Catalog pod: $CATALOG_POD"
    # Try to get bundle info from catalog
    echo "   Checking catalog contents..."
    oc exec -n openshift-marketplace $CATALOG_POD -- ls /configs 2>/dev/null || echo "   Could not access catalog contents"
fi

# Method 4: Check if we can find the operator image directly
echo ""
echo "4. MCE Operator Image (not bundle):"
oc get packagemanifest multicluster-engine -n openshift-marketplace -o json | jq -r '.status.channels[] | select(.name=="stable-2.8") | .currentCSVDesc.relatedImages[]? | select(.name=="multicluster-engine-rhel8-operator") | .image' 2>/dev/null || echo "Not found"

# Method 5: Try a known working image
echo ""
echo "5. Known MCE 2.8 images:"
echo "   Operator: registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator:v2.8.2"
echo "   Bundle: registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator-bundle:v2.8.2"