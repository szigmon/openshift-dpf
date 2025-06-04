#!/bin/bash
# manifests.sh - Manifest management operations

# Exit on error
set -e

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

# Function to prepare DPF manifests and install operator
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

    # Authenticate helm with NGC registry using pull secret
    if [ -f "$DPF_PULL_SECRET" ]; then
        NGC_USERNAME=$(jq -r '.auths."nvcr.io".username' "$DPF_PULL_SECRET")
        NGC_PASSWORD=$(jq -r '.auths."nvcr.io".password' "$DPF_PULL_SECRET")
        log "INFO" "Authenticating helm with NGC registry..."
        helm registry login nvcr.io --username "$NGC_USERNAME" --password "$NGC_PASSWORD" >/dev/null 2>&1 || true
    fi

    # Install/upgrade DPF Operator using helm (idempotent operation)
    log "INFO" "Installing/upgrading DPF Operator to $DPF_VERSION..."
    
    # Construct the full chart URL with version
    CHART_URL="${DPF_HELM_REPO_URL}-${DPF_VERSION}.tgz"
    
    # Install without --wait for immediate feedback
    if helm upgrade --install dpf-operator \
        "${CHART_URL}" \
        --namespace dpf-operator-system \
        --create-namespace \
        --values "${HELM_CHARTS_DIR}/dpf-operator-values.yaml"; then
        
        log "INFO" "Helm release 'dpf-operator' deployed successfully"
        
        # Monitor deployment status
        log "INFO" "Monitoring deployment progress..."
        log "INFO" "Checking pod status in dpf-operator-system namespace..."
        
        # Wait for pods to start (give it a moment)
        sleep 5
        
        # Show current status
        if command -v kubectl >/dev/null 2>&1; then
            kubectl get pods -n dpf-operator-system 2>/dev/null || true
        elif command -v oc >/dev/null 2>&1; then
            oc get pods -n dpf-operator-system 2>/dev/null || true
        fi
        
        log "INFO" "DPF Operator deployment initiated. Use 'kubectl get pods -n dpf-operator-system' to monitor progress."
        log "INFO" "Installation typically takes 2-5 minutes for all pods to become ready."
    else
        log "ERROR" "Helm deployment failed"
        return 1
    fi

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
    
    # Apply static manifests that are not included in the helm chart
    log "INFO" "Applying static DPF manifests..."
    
    # Get kubeconfig if needed
    get_kubeconfig
    
    # Apply each static manifest
    for file in "$GENERATED_DIR"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            log "INFO" "Applying static manifest: ${filename}"
            if command -v kubectl >/dev/null 2>&1; then
                kubectl apply -f "$file" || log "WARN" "Failed to apply $filename"
            elif command -v oc >/dev/null 2>&1; then
                oc apply -f "$file" || log "WARN" "Failed to apply $filename"
            fi
        fi
    done
    
    log "INFO" "Static DPF manifests applied successfully"
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
    sed -i -E 's/:[[:space:]]+/: /g' "$GENERATED_DIR/temp/values.yaml"

    # Pull and template OVN chart
    helm pull oci://ghcr.io/nvidia/ovn-kubernetes-chart \
        --version "$DPF_VERSION" \
        --untar -d "$GENERATED_DIR/temp"
    helm template -n ovn-kubernetes ovn-kubernetes \
        "$GENERATED_DIR/temp/ovn-kubernetes-chart" \
        -f "$GENERATED_DIR/temp/values.yaml" \
        > "$GENERATED_DIR/ovn-manifests.yaml"
    rm -rf "$GENERATED_DIR/temp"

    # Update paths in manifests
    log [INFO] "Updating paths in manifests..."
    sed -i 's|path: /etc/cni/net.d|path: /run/multus/cni/net.d|g' "$GENERATED_DIR/ovn-manifests.yaml"
    sed -i 's|path: /opt/cni/bin|path: /var/lib/cni/bin/|g' "$GENERATED_DIR/ovn-manifests.yaml"
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