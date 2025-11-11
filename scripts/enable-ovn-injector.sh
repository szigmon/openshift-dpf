#!/bin/bash
# enable-ovn-injector.sh - Enable OVN resource injector

# Exit on error
set -e

# Source common utilities and configuration
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"

# Set cluster-specific values
API_SERVER="api.$CLUSTER_NAME.$BASE_DOMAIN:6443"

# Get kubeconfig
get_kubeconfig

# Ensure helm is installed
ensure_helm_installed

log [INFO] "Enabling OVN resource injector..."

rm -rf "$GENERATED_DIR/ovn-injector" | true
mkdir -p "$GENERATED_DIR/ovn-injector"

INJECTOR_RESOURCE_NAME="${INJECTOR_RESOURCE_NAME:-openshift.io/bf3-p0-vfs}"

helm pull "${OVN_CHART_URL}/ovn-kubernetes-chart" \
    --version "${INJECTOR_CHART_VERSION}" \
    --untar -d "$GENERATED_DIR/ovn-injector"

injector_image_params=()
if [ -n "${INJECTOR_IMAGE:-}" ]; then
    injector_image_params=(
        --set "ovn-kubernetes-resource-injector.controllerManager.webhook.image.repository=${INJECTOR_IMAGE%:*}"
        --set "ovn-kubernetes-resource-injector.controllerManager.webhook.image.tag=${INJECTOR_IMAGE#*:}"
    )
fi

helm template -n ${OVNK_NAMESPACE} ovn-kubernetes-resource-injector \
    "$GENERATED_DIR/ovn-injector/ovn-kubernetes-chart" \
    --set ovn-kubernetes-resource-injector.enabled=true \
    --set ovn-kubernetes-resource-injector.resourceName="${INJECTOR_RESOURCE_NAME}" \
    --set ovn-kubernetes-resource-injector.nadName=dpf-ovn-kubernetes \
    "${injector_image_params[@]}" \
    --set nodeWithDPUManifests.enabled=false \
    --set nodeWithoutDPUManifests.enabled=false \
    --set dpuManifests.enabled=false \
    --set controlPlaneManifests.enabled=false \
    --set commonManifests.enabled=false \
    | oc apply -f -

rm -rf "$GENERATED_DIR/ovn-injector"


# Wait for injector to be ready
log [INFO] "Waiting for OVN injector deployment to be ready..."
wait_for_pods "${OVNK_NAMESPACE}" "app.kubernetes.io/name=ovn-kubernetes-resource-injector" 30 10

# Verify NAD creation
if oc get net-attach-def -n "${OVNK_NAMESPACE}" dpf-ovn-kubernetes &>/dev/null; then
    log [INFO] "NetworkAttachmentDefinition 'dpf-ovn-kubernetes' created successfully"
else
    log [ERROR] "NetworkAttachmentDefinition 'dpf-ovn-kubernetes' was not created"
    exit 1
fi

log [INFO] "OVN resource injector enabled successfully"
