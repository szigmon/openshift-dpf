#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Installing HyperShift Directly (without MCE) ==="
echo ""

# Check if hypershift CLI is available
if ! command -v hypershift &>/dev/null; then
    echo "Installing hypershift CLI..."
    # Install hypershift binary
    CONTAINER_COMMAND=${CONTAINER_COMMAND:-podman}
    $CONTAINER_COMMAND cp $($CONTAINER_COMMAND create --name hypershift --rm --pull always ${HYPERSHIFT_IMAGE:-quay.io/hypershift/hypershift-operator:latest}):/usr/bin/hypershift /tmp/hypershift
    $CONTAINER_COMMAND rm -f hypershift
    sudo install -m 0755 -o root -g root /tmp/hypershift /usr/local/bin/hypershift
    rm -f /tmp/hypershift
fi

echo "1. Installing HyperShift operator..."
hypershift install --hypershift-image ${HYPERSHIFT_IMAGE:-quay.io/hypershift/hypershift-operator:latest}

echo ""
echo "2. Waiting for HyperShift operator..."
wait_for_pods "hypershift" "app=operator" "status.phase=Running" "1/1" 30 5 || true

echo ""
echo "3. Checking installation..."
oc get pods -n hypershift
oc get crd | grep hypershift.openshift.io

echo ""
echo "✓ HyperShift installed successfully!"
echo ""
echo "You can now create the HostedCluster by running:"
echo "  make deploy-hosted-cluster"