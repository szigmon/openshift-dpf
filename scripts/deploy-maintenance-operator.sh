#!/bin/bash

# Deploy Maintenance Operator for DPF v25.7
# This operator manages node maintenance operations and ensures graceful handling of node updates
#
# Values are externalized to: manifests/dpf-installation/maintenance-operator-values.yaml
#
# Note: This is a required prerequisite for DPF v25.7 as specified in:
# doca-platform/docs/public/user-guides/prerequisites/helm-prerequisites.md
#
# Helm 3 automatically installs CRDs from the chart's crds/ directory during installation

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/env.sh"

# Configuration
MAINTENANCE_NAMESPACE="dpf-operator-system"
MAINTENANCE_CHART="oci://ghcr.io/mellanox/maintenance-operator-chart"
MAINTENANCE_VERSION="0.2.0"

# Deploy Maintenance Operator
log [INFO] "Deploying Maintenance Operator for DPF v25.7..."

# Get kubeconfig by calling the cluster script
"${SCRIPT_DIR}/cluster.sh" get-kubeconfig

# Note: Helm 3 automatically installs CRDs from the chart's crds/ directory

# Use external values file
MAINTENANCE_VALUES_FILE="${SCRIPT_DIR}/../manifests/dpf-installation/maintenance-operator-values.yaml"

# Verify values file exists
if [ ! -f "$MAINTENANCE_VALUES_FILE" ]; then
    log [ERROR] "Maintenance Operator values file not found: $MAINTENANCE_VALUES_FILE"
    exit 1
fi

log [INFO] "Using Maintenance Operator values from: $MAINTENANCE_VALUES_FILE"

# Install Maintenance Operator
log [INFO] "Installing Maintenance Operator chart version ${MAINTENANCE_VERSION}..."
helm upgrade --install maintenance-operator ${MAINTENANCE_CHART} \
    --namespace ${MAINTENANCE_NAMESPACE} \
    --create-namespace \
    --version ${MAINTENANCE_VERSION} \
    --values ${MAINTENANCE_VALUES_FILE} \
    --wait

# Verify deployment
log [INFO] "Verifying Maintenance Operator deployment..."
kubectl wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=maintenance-operator -n ${MAINTENANCE_NAMESPACE} || true

log [INFO] "Maintenance Operator deployment complete!"
log [INFO] "You can now deploy DPF operator using: make deploy-dpf"