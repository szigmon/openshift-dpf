#!/bin/bash

echo "Checking ACM and MCE options..."
echo ""

echo "1. MCE PackageManifests:"
oc get packagemanifest | grep -E "multicluster-engine|mce" | awk '{print $1, $2, $3}'
echo ""

echo "2. ACM PackageManifests:"
oc get packagemanifest | grep -E "advanced-cluster-management|acm" | awk '{print $1, $2, $3}'
echo ""

echo "3. All operators with 'cluster' in name:"
oc get packagemanifest | grep -i cluster | grep -E "multi|advance" | awk '{print $1, $2, $3}'
echo ""

echo "4. Checking for stolostron (upstream MCE/ACM):"
oc get packagemanifest | grep -i stolostron
echo ""

echo "5. All Red Hat operators with hypershift capability:"
oc get packagemanifest -o json | jq -r '.items[] | select(.status.catalogSource == "redhat-operators") | select(.metadata.name | contains("cluster")) | .metadata.name' | sort

echo ""
echo "6. Existing subscriptions that might provide HyperShift:"
oc get subscription -A | grep -E "multicluster|acm|cluster-management"