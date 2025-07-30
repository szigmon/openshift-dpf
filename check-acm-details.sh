#!/bin/bash

echo "Checking ACM (Advanced Cluster Management) details..."
echo ""

echo "1. ACM available channels:"
oc get packagemanifest advanced-cluster-management -o jsonpath='{.status.channels[*].name}' | tr ' ' '\n' | sort -V
echo ""

echo "2. ACM default channel:"
oc get packagemanifest advanced-cluster-management -o jsonpath='{.status.defaultChannel}'
echo ""

echo "3. ACM versions per channel:"
oc get packagemanifest advanced-cluster-management -o json | jq -r '.status.channels[] | "\(.name): \(.currentCSV)"' | sort
echo ""

echo "4. Current MCE subscription status:"
oc get subscription -n multicluster-engine multicluster-engine -o json 2>/dev/null | jq -r '.status.conditions[] | "\(.type): \(.message)"'