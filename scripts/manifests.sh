#!/bin/bash
# manifests.sh - Manifest management operations

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"

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
     if [[ "${VM_COUNT}" = "1" ]]; then
        log "INFO" "Copying NFS manifest: nfs-sno.yaml (VM count is 1)"
        sed -e "s|<STORAGECLASS_NAME>|${ETCD_STORAGE_CLASS}|g" \
            -e "s|<NFS_SERVER_NODE_IP>|${HOST_CLUSTER_API}|g" \
        "${MANIFESTS_DIR}/nfs/nfs-sno.yaml" > "${GENERATED_DIR}/nfs-sno.yaml"
    fi
}


function prepare_cluster_manifests() {
    log [INFO] "Preparing cluster installation manifests..."
    
    # Copy all manifests
    log [INFO] "Copying static manifests..."
    find "$MANIFESTS_DIR/cluster-installation" -maxdepth 1 -type f -name "*.yaml" -o -name "*.yml" \
        | grep -v "ovn-values.yaml" \
        | grep -v "ovn-values-with-injector.yaml" \
        | xargs -I {} cp {} "$GENERATED_DIR/"

    # Configure cluster components
    log [INFO] "Configuring cluster installation..."
    aicli update installconfig "$CLUSTER_NAME" -P network_type=NVIDIA-OVN

    # Generate Cert-Manager manifests if enabled
    if [ "$ENABLE_CERT_MANAGER" = "true" ]; then
        log [INFO] "Generating Cert-Manager manifests..."
        cp "$MANIFESTS_DIR/cluster-installation/openshift-cert-manager.yaml" "$GENERATED_DIR/"
    else
        log [INFO] "Skipping Cert-Manager manifests (ENABLE_CERT_MANAGER=false)"
    fi

    generate_ovn_manifests
    enable_storage
    
    # Install manifests to cluster
    log [INFO] "Installing manifests to cluster via AICLI..."
    aicli create manifests --dir "$GENERATED_DIR" "$CLUSTER_NAME"

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

    # Check cluster type specific requirements
    if [ "$DPF_CLUSTER_TYPE" = "kamaji" ]; then
      if [ -z "$KAMAJI_VIP" ]; then
        echo "Error: KAMAJI_VIP must be set when using Kamaji cluster type"
        exit 1
      fi
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

    # Process each manifest file
        # Copy all manifests except NFD
    find "$MANIFESTS_DIR/dpf-installation" -maxdepth 1 -type f -name "*.yaml" \
        | xargs -I {} cp {} "$GENERATED_DIR/"

    helm template -n dpf-operator-system dpf-operator oci://ghcr.io/nvidia/dpf-operator \
    --version v25.1.1 -f "${HELM_CHARTS_DIR}/dpf-operator-values.yaml"  > "${GENERATED_DIR}/00-dpf-operator-manifests.yaml"
    log "INFO" "DPF manifest preparation completed successfully"


    # Update manifests with configuration
    sed -i "s|storageClassName: \"\"|storageClassName: \"$BFB_STORAGE_CLASS\"|g" "$GENERATED_DIR/bfb-pvc.yaml"


    # Update static DPU cluster template
    sed -i "s|KUBERNETES_VERSION|$OPENSHIFT_VERSION|g" "$GENERATED_DIR/static-dpucluster-template.yaml"
    sed -i "s|HOSTED_CLUSTER_NAME|$HOSTED_CLUSTER_NAME|g" "$GENERATED_DIR/static-dpucluster-template.yaml"

    # Extract NGC API key and update secrets
    NGC_API_KEY=$(jq -r '.auths."nvcr.io".password' "$DPF_PULL_SECRET")
    sed -i "s|<PASSWORD>|$NGC_API_KEY|g" "$GENERATED_DIR/ngc-secrets.yaml"

    # Update pull secret
    PULL_SECRET=$(cat "$DPF_PULL_SECRET" | base64 -w 0)
    sed -i "s|PULL_SECRET_BASE64|$PULL_SECRET|g" "$GENERATED_DIR/dpf-pull-secret.yaml"

    prepare_nfs
}

function generate_ovn_manifests() {
    log [INFO] "Generating OVN manifests for cluster installation..."
    
    # NOTE: We must use helm template here because these manifests are added to the cluster
    # via 'aicli create manifests' before the cluster API is available for helm install
    
    # Ensure helm is installed
    ensure_helm_installed
    
    mkdir -p "$GENERATED_DIR/temp"
    local API_SERVER="api.$CLUSTER_NAME.$BASE_DOMAIN:6443"
    
    # Pull and template OVN chart v2 (no sed needed with custom chart)
    helm pull oci://quay.io/szigmon/ovn \
        --version "v25.4.0-custom-v2" \
        --untar -d "$GENERATED_DIR/temp"
    
    # Replace template variables in values file
    sed -e "s|<TARGETCLUSTER_API_SERVER_HOST>|api.$CLUSTER_NAME.$BASE_DOMAIN|" \
        -e "s|<TARGETCLUSTER_API_SERVER_PORT>|6443|" \
        -e "s|<POD_CIDR>|$POD_CIDR|" \
        -e "s|<SERVICE_CIDR>|$SERVICE_CIDR|" \
        -e "s|<DPU_P0_VF1>|$DPU_OVN_VF|" \
        -e "s|<DPU_P0>|$DPU_INTERFACE|" \
        "$MANIFESTS_DIR/cluster-installation/ovn-values.yaml" > "$GENERATED_DIR/temp/ovn-values-resolved.yaml"
    
    helm template -n ovn-kubernetes ovn-kubernetes \
        "$GENERATED_DIR/temp/ovn" \
        -f "$GENERATED_DIR/temp/ovn-values-resolved.yaml" \
        > "$GENERATED_DIR/ovn-manifests.yaml"
    
    rm -rf "$GENERATED_DIR/temp"
    
    log [INFO] "OVN manifests generated successfully"
}

function enable_storage() {
    log [INFO] "Enabling storage operator"
    
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