#!/bin/bash
# enable-ovn-injector.sh - Enable OVN resource injector

# Exit on error
set -e

# Source common utilities and configuration
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"

# Set cluster-specific values
API_SERVER="api.$CLUSTER_NAME.$BASE_DOMAIN:6443"

# Get kubeconfig
get_kubeconfig

# Ensure helm is installed
ensure_helm_installed

log [INFO] "Enabling OVN resource injector..."

# Generate full manifest with injector enabled
mkdir -p "$GENERATED_DIR/ovn-injector"

helm pull oci://quay.io/szigmon/ovn \
    --version "v25.4.0-custom-v2" \
    --untar -d "$GENERATED_DIR/ovn-injector"

# Replace template variables in values file
sed -e "s|<TARGETCLUSTER_API_SERVER_HOST>|$CLUSTER_NAME.$BASE_DOMAIN|" \
    -e "s|<TARGETCLUSTER_API_SERVER_PORT>|6443|" \
    -e "s|<POD_CIDR>|$POD_CIDR|" \
    -e "s|<SERVICE_CIDR>|$SERVICE_CIDR|" \
    -e "s|<DPU_P0_VF1>|$DPU_OVN_VF|" \
    -e "s|<DPU_P0>|$DPU_INTERFACE|" \
    "$MANIFESTS_DIR/cluster-installation/ovn-values-with-injector.yaml" > "$GENERATED_DIR/ovn-injector/ovn-values-resolved.yaml"

# Generate all manifests with injector enabled
helm template -n ovn-kubernetes ovn-kubernetes \
    "$GENERATED_DIR/ovn-injector/ovn" \
    -f "$GENERATED_DIR/ovn-injector/ovn-values-resolved.yaml" \
    | oc apply -f -

# Clean up
rm -rf "$GENERATED_DIR/ovn-injector"

# Wait for injector to be ready
log [INFO] "Waiting for OVN injector deployment to be ready..."
wait_for_pods "ovn-kubernetes" "app.kubernetes.io/name=ovn-kubernetes-resource-injector" "status.phase=Running" "Running" 30 10

# Verify NAD creation
if oc get networkattachmentdefinition -n ovn-kubernetes dpf-ovn-kubernetes &>/dev/null; then
    log [INFO] "NetworkAttachmentDefinition 'dpf-ovn-kubernetes' created successfully"
else
    log [ERROR] "NetworkAttachmentDefinition 'dpf-ovn-kubernetes' was not created"
    exit 1
fi

log [INFO] "OVN resource injector enabled successfully"