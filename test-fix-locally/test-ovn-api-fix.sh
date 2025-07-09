#!/bin/bash
# Test script to verify the api. prefix fix in generate_ovn_manifests

set -e

# Source the environment and scripts
source "$(dirname "$0")/../scripts/env.sh"
source "$(dirname "$0")/../scripts/utils.sh"
source "$(dirname "$0")/../scripts/manifests.sh"

# Create a temporary test directory
TEST_DIR="/tmp/test-ovn-api-fix-$$"
mkdir -p "$TEST_DIR"

# Override some variables for testing
export GENERATED_DIR="$TEST_DIR/generated"
export MANIFESTS_DIR="$(dirname "$0")/../manifests"
export CLUSTER_NAME="test-cluster"
export BASE_DOMAIN="example.com"
export POD_CIDR="10.128.0.0/14"
export SERVICE_CIDR="172.30.0.0/16"
export DPU_OVN_VF="enp3s0f0v1"
export DPU_INTERFACE="enp3s0f0"

# Create the required directory structure
mkdir -p "$GENERATED_DIR"

echo "Testing generate_ovn_manifests function..."
echo "Expected API server: api.$CLUSTER_NAME.$BASE_DOMAIN"
echo ""

# Run the function
generate_ovn_manifests

echo ""
echo "Checking generated manifests for correct API server address..."

# Check if the generated file contains the correct API server address
if grep -q "api.$CLUSTER_NAME.$BASE_DOMAIN" "$GENERATED_DIR/ovn-manifests.yaml"; then
    echo "✓ SUCCESS: Found correct API server address with 'api.' prefix"
    echo ""
    echo "Sample lines containing the API server address:"
    grep -n "api\.$CLUSTER_NAME\.$BASE_DOMAIN" "$GENERATED_DIR/ovn-manifests.yaml" | head -5
else
    echo "✗ FAILURE: Could not find correct API server address with 'api.' prefix"
    echo ""
    echo "Looking for any occurrence of the cluster name:"
    grep -n "$CLUSTER_NAME\.$BASE_DOMAIN" "$GENERATED_DIR/ovn-manifests.yaml" | head -5 || echo "No matches found"
fi

# Also check the intermediate values file
echo ""
echo "Checking intermediate values file..."
if [ -f "$GENERATED_DIR/temp/ovn-values-resolved.yaml" ]; then
    echo "Note: Intermediate file was not cleaned up"
    grep -n "api\.$CLUSTER_NAME\.$BASE_DOMAIN" "$GENERATED_DIR/temp/ovn-values-resolved.yaml" || true
fi

# Clean up
echo ""
echo "Cleaning up test directory: $TEST_DIR"
rm -rf "$TEST_DIR"

echo ""
echo "Test completed!"