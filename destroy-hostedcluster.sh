#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=========================================="
echo "Destroy HostedCluster using hypershift CLI"
echo "=========================================="
echo ""

# Check if hypershift CLI is available
if ! command -v hypershift &> /dev/null; then
    echo "ERROR: hypershift CLI not found!"
    echo "Install it with: make install-hypershift"
    exit 1
fi

# Check if HostedCluster exists
if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
    echo "Found HostedCluster: ${HOSTED_CLUSTER_NAME} in namespace: ${CLUSTERS_NAMESPACE}"
    echo ""
    read -p "Are you sure you want to destroy it? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Destroy cancelled"
        exit 0
    fi
    
    echo "Destroying HostedCluster..."
    hypershift destroy cluster \
        --name ${HOSTED_CLUSTER_NAME} \
        --namespace ${CLUSTERS_NAMESPACE} \
        --destroy-cloud-resources
    
    echo "HostedCluster destroyed successfully!"
else
    echo "HostedCluster ${HOSTED_CLUSTER_NAME} not found in namespace ${CLUSTERS_NAMESPACE}"
fi