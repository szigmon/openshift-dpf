#!/bin/bash

echo "Checking what's blocking HostedCluster deletion..."
echo ""

echo "1. HostedCluster finalizers:"
oc get hostedcluster -n clusters doca -o json | jq '.metadata.finalizers'

echo ""
echo "2. HostedCluster deletion timestamp:"
oc get hostedcluster -n clusters doca -o json | jq '.metadata.deletionTimestamp'

echo ""
echo "3. HostedCluster conditions:"
oc get hostedcluster -n clusters doca -o json | jq '.status.conditions[] | select(.type == "DegradedConfiguration" or .type == "Progressing")'

echo ""
echo "4. Control plane resources:"
oc get all -n clusters-doca --no-headers 2>/dev/null | wc -l | xargs echo "Number of resources:"

echo ""
echo "5. HostedControlPlane status:"
oc get hostedcontrolplanes -A 2>/dev/null || echo "No HostedControlPlanes found"

echo ""
echo "6. Recent events:"
oc get events -n clusters --field-selector involvedObject.name=doca --sort-by='.lastTimestamp' | tail -5