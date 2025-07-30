#!/bin/bash

# Quick script to destroy the HostedCluster immediately

echo "Destroying HostedCluster 'doca' in namespace 'clusters'..."

hypershift destroy cluster none \
    --name doca \
    --namespace clusters

echo "Destroy command executed. Checking status..."

# Wait a bit and check if it's gone
sleep 5

if oc get hostedcluster -n clusters doca &>/dev/null; then
    echo "HostedCluster still exists. It may take a few minutes to fully delete."
    echo "You can monitor with: watch 'oc get hostedcluster -A'"
else
    echo "HostedCluster has been removed successfully!"
fi