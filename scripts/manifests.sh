#!/bin/bash
# manifests.sh - Manifest management operations

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# -----------------------------------------------------------------------------
# Manifest preparation functions
# -----------------------------------------------------------------------------
function prepare_manifests() {
    local manifest_type=$1
    log "Preparing $manifest_type manifests..."
    
    # Clean and recreate generated directory
    rm -rf "$GENERATED_DIR"
    mkdir -p "$GENERATED_DIR"

    case "$manifest_type" in
        cluster)
            prepare_cluster_manifests
            ;;
        dpf)
            prepare_dpf_manifests
            ;;
        *)
            log "Error: Unknown manifest type: $manifest_type"
            log "Valid types are: cluster, dpf"
            exit 1
            ;;
    esac
}

function prepare_cluster_manifests() {
    log "Preparing cluster installation manifests..."
    
    # Copy all manifests
    log "Copying static manifests..."
    find "$MANIFESTS_DIR/cluster-installation" -maxdepth 1 -type f -name "*.yaml" -o -name "*.yml" \
        | grep -v "ovn-values.yaml" \
        | xargs -I {} cp {} "$GENERATED_DIR/"

    # Configure cluster components
    log "Configuring cluster installation..."
    aicli update installconfig "$CLUSTER_NAME" -P network_type=NVIDIA-OVN

    # Generate Cert-Manager manifests if enabled
    if [ "$ENABLE_CERT_MANAGER" = "true" ]; then
        log "Generating Cert-Manager manifests..."
        cp "$MANIFESTS_DIR/cluster-installation/openshift-cert-manager.yaml" "$GENERATED_DIR/"
    else
        log "Skipping Cert-Manager manifests (ENABLE_CERT_MANAGER=false)"
    fi

    generate_ovn_manifests
    enable_storage
    
    # Install manifests to cluster
    log "Installing manifests to cluster via AICLI..."
    aicli create manifests --dir "$GENERATED_DIR" "$CLUSTER_NAME"

    log "Cluster manifests preparation complete."
}

function prepare_dpf_manifests() {
    log "Preparing DPF manifests..."
    
    # Validate required variables
    if [ -z "$HOST_CLUSTER_API" ]; then
        log "Error: HOST_CLUSTER_API must be set"
        exit 1
    fi

    if [ -z "$DPU_INTERFACE" ]; then
        log "Error: DPU_INTERFACE must be set"
        exit 1
    fi

    # Only validate KAMAJI_VIP if using kamaji cluster type
    if [ "${DPF_CLUSTER_TYPE}" = "kamaji" ] && [ -z "$KAMAJI_VIP" ]; then
        log "Error: KAMAJI_VIP must be set when using kamaji cluster type"
        exit 1
    fi

    # Copy all manifests except NFD
    find "$MANIFESTS_DIR/dpf-installation" -maxdepth 1 -type f -name "*.yaml" \
        | grep -v "dpf-nfd.yaml" \
        | xargs -I {} cp {} "$GENERATED_DIR/"

    # Update manifests with configuration
    sed -i "s|value: api.CLUSTER_FQDN|value: $HOST_CLUSTER_API|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"
    sed -i "s|storageClassName: lvms-vg1|storageClassName: $ETCD_STORAGE_CLASS|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"
    sed -i "s|storageClassName: lvms-vg1|storageClassName: $ETCD_STORAGE_CLASS|g" "$GENERATED_DIR/kamaji-manifests.yaml"
    sed -i "s|storageClassName: \"\"|storageClassName: \"$BFB_STORAGE_CLASS\"|g" "$GENERATED_DIR/bfb-pvc.yaml"

    # Extract NGC API key and update secrets
    local NGC_API_KEY=$(jq -r '.auths."nvcr.io".password' "$DPF_PULL_SECRET")
    sed -i "s|password: xxx|password: $NGC_API_KEY|g" "$GENERATED_DIR/ngc-secrets.yaml"

    # Update interface configurations
    sed -i "s|ens7f0np0|$DPU_INTERFACE|g" "$GENERATED_DIR/sriov-policy.yaml"
    sed -i "s|interface: br-ex|interface: $DPU_INTERFACE|g" "$GENERATED_DIR/kamaji-manifests.yaml"
    
    # Only update KAMAJI_VIP if using kamaji cluster type
    if [ "${DPF_CLUSTER_TYPE}" = "kamaji" ]; then
        sed -i "s|vip: KAMAJI_VIP|vip: $KAMAJI_VIP|g" "$GENERATED_DIR/kamaji-manifests.yaml"
    fi

    # Update pull secret
    local PULL_SECRET=$(cat "$DPF_PULL_SECRET" | base64 -w 0)
    sed -i "s|.dockerconfigjson: = xxx|.dockerconfigjson: $PULL_SECRET|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"

    log "DPF manifests prepared successfully."
}

function generate_ovn_manifests() {
    log "Generating OVN manifests..."
    
    # Ensure helm is installed
    ensure_helm_installed
    
    mkdir -p "$GENERATED_DIR/temp"
    local API_SERVER="api.$CLUSTER_NAME.$BASE_DOMAIN:6443"
    
    sed -e "s|k8sAPIServer:.*|k8sAPIServer: https://$API_SERVER|" \
        -e "s|podNetwork:.*|podNetwork: $POD_CIDR|" \
        -e "s|serviceNetwork:.*|serviceNetwork: $SERVICE_CIDR|" \
        -e "s|nodeMgmtPortNetdev:.*|nodeMgmtPortNetdev: $DPU_OVN_VF|" \
        -e "s|gatewayOpts:.*|gatewayOpts: --gateway-interface=$DPU_INTERFACE|" \
        "$MANIFESTS_DIR/cluster-installation/ovn-values.yaml" > "$GENERATED_DIR/temp/values.yaml"
    sed -i -E 's/:[[:space:]]+/: /g' "$GENERATED_DIR/temp/values.yaml"

    # Pull and template OVN chart
    helm pull oci://ghcr.io/nvidia/ovn-kubernetes-chart \
        --version "$HELM_CHART_VERSION" \
        --untar -d "$GENERATED_DIR/temp"
    helm template -n ovn-kubernetes ovn-kubernetes \
        "$GENERATED_DIR/temp/ovn-kubernetes-chart" \
        -f "$GENERATED_DIR/temp/values.yaml" \
        > "$GENERATED_DIR/ovn-manifests.yaml"
    rm -rf "$GENERATED_DIR/temp"

    # Update paths in manifests
    log "Updating paths in manifests..."
    sed -i 's|path: /etc/cni/net.d|path: /run/multus/cni/net.d|g' "$GENERATED_DIR/ovn-manifests.yaml"
    sed -i 's|path: /opt/cni/bin|path: /var/lib/cni/bin/|g' "$GENERATED_DIR/ovn-manifests.yaml"
}

function enable_storage() {
    log "Enabling storage operator"
    
    if [ "$VM_COUNT" -eq 1 ]; then
        log "Enable LVM operator"
        aicli update cluster "$CLUSTER_NAME" -P olm_operators='[{"name": "lvm"}]'
    else
        log "Enable ODF operator"
        aicli update cluster "$CLUSTER_NAME" -P olm_operators='[{"name": "odf"}]'
    fi
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    case "$command" in
        prepare-manifests)
            prepare_manifests "cluster"
            ;;
        prepare-dpf-manifests)
            prepare_manifests "dpf"
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: prepare-manifests, prepare-dpf-manifests"
            exit 1
            ;;
    esac
}

# If script is executed directly (not sourced), run the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log "Usage: $0 <command> [arguments...]"
        exit 1
    fi
    
    main "$@"
fi 