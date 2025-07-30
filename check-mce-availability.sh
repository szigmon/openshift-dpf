#!/bin/bash

echo "Checking MCE availability across all catalogs..."
echo ""

# Check all available channels for MCE
echo "1. Available MCE channels:"
oc get packagemanifest multicluster-engine -o jsonpath='{.status.channels[*].name}' | tr ' ' '\n' | sort -V
echo ""

# Check which catalog provides MCE
echo "2. Catalog providing MCE:"
oc get packagemanifest multicluster-engine -o jsonpath='{.status.catalogSource}'
echo ""

# Check default channel
echo "3. Default channel:"
oc get packagemanifest multicluster-engine -o jsonpath='{.status.defaultChannel}'
echo ""

# Check all versions available
echo "4. All available versions:"
oc get packagemanifest multicluster-engine -o json | jq -r '.status.channels[] | "\(.name): \(.currentCSV)"'
echo ""

# Check if there are multiple MCE packagemanifests
echo "5. All MCE packagemanifests:"
oc get packagemanifest | grep -i multicluster

# Check current subscription status
echo ""
echo "6. Current subscription status:"
oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || echo "No subscription found"

# Check if 2.11 is available in any catalog
echo ""
echo "7. Searching for MCE 2.11 in all catalogs:"
for catalog in $(oc get catalogsource -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --no-headers); do
    name=$(echo $catalog | awk '{print $1}')
    ns=$(echo $catalog | awk '{print $2}')
    echo "   Checking $name in $ns..."
    oc get packagemanifest -l "catalog=$name" 2>/dev/null | grep -i multicluster || true
done