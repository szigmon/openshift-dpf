#!/bin/bash

echo "=== MCE (MultiCluster Engine) Channel Information ==="
echo ""

echo "1. Available MCE channels:"
oc get packagemanifest multicluster-engine -o jsonpath='{.status.channels[*].name}' | tr ' ' '\n' | sort -V
echo ""

echo "2. Default MCE channel:"
oc get packagemanifest multicluster-engine -o jsonpath='{.status.defaultChannel}'
echo ""

echo "3. MCE versions per channel:"
oc get packagemanifest multicluster-engine -o json | jq -r '.status.channels[] | "\(.name): \(.currentCSV)"' | sort
echo ""

echo "4. Catalog source for MCE:"
oc get packagemanifest multicluster-engine -o jsonpath='{.status.catalogSource}'
echo ""

echo "5. All operators with 'engine' in name:"
oc get packagemanifest | grep -i engine | grep -v acm