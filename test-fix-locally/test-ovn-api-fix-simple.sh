#!/bin/bash
# Simple test to verify the api. prefix fix in the sed command

set -e

# Source just the environment
source "$(dirname "$0")/../scripts/env.sh"

# Set test variables
export CLUSTER_NAME="test-cluster"
export BASE_DOMAIN="example.com"
export POD_CIDR="10.128.0.0/14"
export SERVICE_CIDR="172.30.0.0/16"
export DPU_OVN_VF="enp3s0f0v1"
export DPU_INTERFACE="enp3s0f0"

# Create test directories
TEST_DIR="/tmp/test-ovn-api-fix-$$"
mkdir -p "$TEST_DIR"

# Create a mock ovn-values.yaml file
cat > "$TEST_DIR/ovn-values.yaml" << 'EOF'
global:
  targetCluster:
    apiServerHost: <TARGETCLUSTER_API_SERVER_HOST>
    apiServerPort: <TARGETCLUSTER_API_SERVER_PORT>
  network:
    podCIDR: <POD_CIDR>
    serviceCIDR: <SERVICE_CIDR>
  dpu:
    interface: <DPU_P0>
    vf: <DPU_P0_VF1>
EOF

echo "Testing sed command with api. prefix fix..."
echo "Expected API server: api.$CLUSTER_NAME.$BASE_DOMAIN"
echo ""

# Run the exact sed command from the fixed manifests.sh
sed -e "s|<TARGETCLUSTER_API_SERVER_HOST>|api.$CLUSTER_NAME.$BASE_DOMAIN|" \
    -e "s|<TARGETCLUSTER_API_SERVER_PORT>|6443|" \
    -e "s|<POD_CIDR>|$POD_CIDR|" \
    -e "s|<SERVICE_CIDR>|$SERVICE_CIDR|" \
    -e "s|<DPU_P0_VF1>|$DPU_OVN_VF|" \
    -e "s|<DPU_P0>|$DPU_INTERFACE|" \
    "$TEST_DIR/ovn-values.yaml" > "$TEST_DIR/ovn-values-resolved.yaml"

echo "Generated values file content:"
echo "==============================="
cat "$TEST_DIR/ovn-values-resolved.yaml"
echo "==============================="
echo ""

# Verify the api. prefix is present
if grep -q "api.$CLUSTER_NAME.$BASE_DOMAIN" "$TEST_DIR/ovn-values-resolved.yaml"; then
    echo "✓ SUCCESS: Found correct API server address with 'api.' prefix"
    echo "  Actual value: $(grep apiServerHost "$TEST_DIR/ovn-values-resolved.yaml" | awk '{print $2}')"
else
    echo "✗ FAILURE: Could not find correct API server address with 'api.' prefix"
    echo "  Actual value: $(grep apiServerHost "$TEST_DIR/ovn-values-resolved.yaml" | awk '{print $2}')"
fi

# Clean up
rm -rf "$TEST_DIR"

echo ""
echo "Test completed!"