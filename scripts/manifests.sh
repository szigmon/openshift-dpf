#!/bin/bash
# manifests.sh - Manifest management operations

# Exit on error and catch pipe failures
set -e
set -o pipefail

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"

HOST_CLUSTER_API=${HOST_CLUSTER_API:-"api.$CLUSTER_NAME.$BASE_DOMAIN"}

# -----------------------------------------------------------------------------
# Manifest preparation functions
# -----------------------------------------------------------------------------
function prepare_manifests() {
    local manifest_type=$1
    log [INFO] "Preparing $manifest_type manifests..."
    
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
            log [INFO] "Error: Unknown manifest type: $manifest_type"
            log [INFO] "Valid types are: cluster, dpf"
            exit 1
            ;;
    esac
}


function prepare_nfs() {
    # Deploy NFS when ReadWriteMany storage is needed but OCS/ODF is unavailable
    # Two scenarios require NFS:
    # 1. Small clusters (VM_COUNT < 3) that lack OCS/ODF storage classes
    # 2. Explicit NFS configuration (BFB_STORAGE_CLASS="nfs-client") regardless of cluster size
    local needs_nfs=false
    local reason=""
    
    if [[ "${VM_COUNT}" -lt 3 ]]; then
        needs_nfs=true
        reason="small cluster without OCS (VM_COUNT=${VM_COUNT})"
    elif [[ "${BFB_STORAGE_CLASS}" == "nfs-client" ]]; then
        needs_nfs=true
        reason="explicit NFS configuration (BFB_STORAGE_CLASS=nfs-client)"
    fi
    
    if [[ "$needs_nfs" == "true" ]]; then
        log "INFO" "Deploying NFS for ReadWriteMany storage: ${reason}"
        # Validate ETCD_STORAGE_CLASS is set
        if [ -z "${ETCD_STORAGE_CLASS}" ]; then
            log "ERROR" "ETCD_STORAGE_CLASS is not set but required for NFS deployment"
            return 1
        fi
        sed -e "s|<STORAGECLASS_NAME>|${ETCD_STORAGE_CLASS}|g" \
            -e "s|<NFS_SERVER_NODE_IP>|${HOST_CLUSTER_API}|g" \
        "${MANIFESTS_DIR}/nfs/nfs-sno.yaml" > "${GENERATED_DIR}/nfs-sno.yaml"
    else
        log "INFO" "Skipping NFS deployment: using OCS/ODF storage (VM_COUNT=${VM_COUNT})"
    fi
}


function prepare_cluster_manifests() {
    log [INFO] "Preparing cluster installation manifests..."
    
    # Copy all manifests
    log [INFO] "Copying static manifests..."
    find "$MANIFESTS_DIR/cluster-installation" -maxdepth 1 -type f -name "*.yaml" -o -name "*.yml" \
        | grep -v "ovn-values.yaml" \
        | xargs -I {} cp {} "$GENERATED_DIR/"

    # Configure cluster components
    log [INFO] "Configuring cluster installation..."
    
    # Check if cluster is already installed
    if check_cluster_installed; then
        log [INFO] "Skipping configuration updates as cluster is already installed"
    else
        aicli update installconfig "$CLUSTER_NAME" -P network_type=NVIDIA-OVN
    fi

    # Always copy Cert-Manager manifest (required for DPF operator)
    log [INFO] "Copying Cert-Manager manifest (required for DPF operator)..."
    cp "$MANIFESTS_DIR/cluster-installation/openshift-cert-manager.yaml" "$GENERATED_DIR/"

    generate_ovn_manifests
    enable_storage
    
    # Install manifests to cluster
    # Check if cluster is already installed
    if check_cluster_installed; then
        log [INFO] "Skipping manifest installation as cluster is already installed"
    else
        log [INFO] "Installing manifests to cluster via AICLI..."
        aicli create manifests --dir "$GENERATED_DIR" "$CLUSTER_NAME"
    fi

    log [INFO] "Cluster manifests preparation complete."
}

# Function to prepare DPF manifests
prepare_dpf_manifests() {
    log [INFO] "Starting DPF manifest preparation..."
    echo "Using manifests directory: ${MANIFESTS_DIR}"

    # Check required variables
    if [ -z "$MANIFESTS_DIR" ]; then
      echo "Error: MANIFESTS_DIR must be set"
      exit 1
    fi

    if [ -z "$GENERATED_DIR" ]; then
      echo "Error: GENERATED_DIR must be set"
      exit 1
    fi

    # Validate required variables
    if [ -z "$HOST_CLUSTER_API" ]; then
      echo "Error: HOST_CLUSTER_API must be set"
      exit 1
    fi

    if [ -z "$DPU_INTERFACE" ]; then
      echo "Error: DPU_INTERFACE must be set"
      exit 1
    fi

    # Create generated directory if it doesn't exist
    if [ ! -d "${GENERATED_DIR}" ]; then
        log "INFO" "Creating generated directory: ${GENERATED_DIR}"
        mkdir -p "${GENERATED_DIR}"
    fi

    # Copy and process manifests
    log "INFO" "Processing manifests from ${MANIFESTS_DIR} to ${GENERATED_DIR}"
    
    # Copy all manifests except NFD
    find "$MANIFESTS_DIR/dpf-installation" -maxdepth 1 -type f -name "*.yaml" \
        | xargs -I {} cp {} "$GENERATED_DIR/"

    # Copy cert-manager manifest (required for DPF deployment)
    log "INFO" "Copying Cert-Manager manifest (required for DPF operator)..."
    cp "$MANIFESTS_DIR/cluster-installation/openshift-cert-manager.yaml" "$GENERATED_DIR/"

    log "INFO" "DPF manifest preparation completed successfully"

    # Update manifests with configuration
    # Check if bfb-pvc.yaml exists before modifying
    if [ ! -f "$GENERATED_DIR/bfb-pvc.yaml" ]; then
        log "ERROR" "bfb-pvc.yaml not found in $GENERATED_DIR"
        return 1
    fi
    
    # For single-node clusters (VM_COUNT < 2), we use direct NFS PV binding, so remove storageClassName
    if [ "${VM_COUNT}" -lt 2 ]; then
        if ! grep -v 'storageClassName: ""' "$GENERATED_DIR/bfb-pvc.yaml" > "$GENERATED_DIR/bfb-pvc.yaml.tmp"; then
            log "ERROR" "Failed to process bfb-pvc.yaml for single-node cluster"
            return 1
        fi
        mv "$GENERATED_DIR/bfb-pvc.yaml.tmp" "$GENERATED_DIR/bfb-pvc.yaml"
    else
        sed -i "s|storageClassName: \"\"|storageClassName: \"$BFB_STORAGE_CLASS\"|g" "$GENERATED_DIR/bfb-pvc.yaml"
    fi

    # Update static DPU cluster template
    sed -i "s|KUBERNETES_VERSION|$OPENSHIFT_VERSION|g" "$GENERATED_DIR/static-dpucluster-template.yaml"
    sed -i "s|HOSTED_CLUSTER_NAME|$HOSTED_CLUSTER_NAME|g" "$GENERATED_DIR/static-dpucluster-template.yaml"

    # Extract NGC API key and update secrets
    NGC_API_KEY=$(jq -r '.auths."nvcr.io".password // empty' "$DPF_PULL_SECRET" 2>/dev/null)
    if [ -z "$NGC_API_KEY" ] || [ "$NGC_API_KEY" = "null" ]; then
        log "ERROR" "Failed to extract NGC API key from pull secret"
        return 1
    fi
    local escaped_api_key=$(escape_sed_replacement "$NGC_API_KEY")
    sed -i "s|<PASSWORD>|$escaped_api_key|g" "$GENERATED_DIR/ngc-secrets.yaml"

    # Update pull secret
    # Encode pull secret (Linux/GNU base64)
    PULL_SECRET=$(cat "$DPF_PULL_SECRET" | base64 -w 0)
    if [ -z "$PULL_SECRET" ]; then
        log "ERROR" "Failed to encode pull secret"
        return 1
    fi
    local escaped_secret=$(escape_sed_replacement "$PULL_SECRET")
    sed -i "s|PULL_SECRET_BASE64|$escaped_secret|g" "$GENERATED_DIR/dpf-pull-secret.yaml"

    prepare_nfs
    
    # Process dpfoperatorconfig.yaml - replace cluster-specific values
    process_template \
        "$MANIFESTS_DIR/dpf-installation/dpfoperatorconfig.yaml" \
        "$GENERATED_DIR/dpfoperatorconfig.yaml" \
        "<CLUSTER_NAME>" "$CLUSTER_NAME" \
        "<BASE_DOMAIN>" "$BASE_DOMAIN"
}

function generate_ovn_manifests() {
    log [INFO] "Generating OVN manifests..."
    
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
    sed -E 's/:[[:space:]]+/: /g' "$GENERATED_DIR/temp/values.yaml" > "$GENERATED_DIR/temp/values.yaml.tmp" && mv "$GENERATED_DIR/temp/values.yaml.tmp" "$GENERATED_DIR/temp/values.yaml"

    # Pull and template OVN chart
    log [INFO] "Pulling OVN chart version $DPF_VERSION..."
    if ! helm pull oci://ghcr.io/nvidia/ovn-kubernetes-chart \
        --version "$DPF_VERSION" \
        --untar -d "$GENERATED_DIR/temp"; then
        log [ERROR] "Failed to pull OVN chart version $DPF_VERSION"
        return 1
    fi
    
    log [INFO] "Generating OVN manifests from helm template..."
    if ! helm template -n ovn-kubernetes ovn-kubernetes \
        "$GENERATED_DIR/temp/ovn-kubernetes-chart" \
        -f "$GENERATED_DIR/temp/values.yaml" \
        > "$GENERATED_DIR/ovn-manifests.yaml"; then
        log [ERROR] "Failed to generate OVN manifests"
        return 1
    fi
    
    # Check if the file is not empty
    if [ ! -s "$GENERATED_DIR/ovn-manifests.yaml" ]; then
        log [ERROR] "Generated OVN manifest file is empty!"
        return 1
    fi
    
    rm -rf "$GENERATED_DIR/temp"

    # Update paths in manifests
    log [INFO] "Updating paths in manifests..."
    sed 's|path: /etc/cni/net.d|path: /run/multus/cni/net.d|g' "$GENERATED_DIR/ovn-manifests.yaml" > "$GENERATED_DIR/ovn-manifests.yaml.tmp" && mv "$GENERATED_DIR/ovn-manifests.yaml.tmp" "$GENERATED_DIR/ovn-manifests.yaml"
    sed 's|path: /opt/cni/bin|path: /var/lib/cni/bin/|g' "$GENERATED_DIR/ovn-manifests.yaml" > "$GENERATED_DIR/ovn-manifests.yaml.tmp" && mv "$GENERATED_DIR/ovn-manifests.yaml.tmp" "$GENERATED_DIR/ovn-manifests.yaml"
}

function enable_storage() {
    log [INFO] "Enabling storage operator"
    
    # Check if cluster is already installed
    if check_cluster_installed; then
        log [INFO] "Skipping storage operator configuration as cluster is already installed"
        return 0
    fi
    
    # Update cluster with storage operator
    if [ "$VM_COUNT" -eq 1 ]; then
        log [INFO] "Enable LVM operator"
        aicli update cluster "$CLUSTER_NAME" -P olm_operators='[{"name": "lvm"}]'
    else
        log [INFO] "Enable ODF operator"
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
        generate-ovn-manifests)
            generate_ovn_manifests
            ;;
        prepare-manifests)
            prepare_manifests "cluster"
            ;;
        prepare-dpf-manifests)
            prepare_manifests "dpf"
            ;;
        *)
            log [INFO] "Unknown command: $command"
            log [INFO] "Available commands: prepare-manifests, prepare-dpf-manifests"
            exit 1
            ;;
    esac
}

# If script is executed directly (not sourced), run the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log [INFO] "Usage: $0 <command> [arguments...]"
        exit 1
    fi
    
    main "$@"
fi 