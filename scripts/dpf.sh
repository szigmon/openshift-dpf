#!/bin/bash
# dpf.sh - DPF deployment operations

# Exit on error and catch pipe failures
set -e
set -o pipefail

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"

ETCD_STORAGE_CLASS=${ETCD_STORAGE_CLASS:-"ocs-storagecluster-ceph-rbd"}

# -----------------------------------------------------------------------------
# DPF deployment functions
# -----------------------------------------------------------------------------
function deploy_nfd() {
    log [INFO] "Managing NFD deployment..."

    get_kubeconfig

    # Check if NFD subscription exists, if not apply it
    if ! oc get subscription -n openshift-nfd nfd &>/dev/null; then
        log [INFO] "NFD subscription not found. Applying NFD subscription..."
        apply_manifest "$MANIFESTS_DIR/cluster-installation/nfd-subscription.yaml"
        
        # Verify operator is ready by checking CSV
        log [INFO] "Verifying NFD operator installation..."
        if ! retry 30 10 bash -c 'oc get csv -n openshift-nfd -o jsonpath="{.items[*].status.phase}" | grep -q "Succeeded"'; then
            log [ERROR] "Timeout: NFD operator installation failed"
            return 1
        fi
        log [INFO] "NFD operator installation verified successfully"
    else
        log [INFO] "NFD subscription already exists. Skipping deployment."
    fi

    # Create NFD instance with custom operand image
    log [INFO] "Creating NFD instance with custom operand image..."
    mkdir -p "$GENERATED_DIR"
    cp "$MANIFESTS_DIR/dpf-installation/nfd-cr-template.yaml" "$GENERATED_DIR/nfd-cr-template.yaml"
    echo
    sed -i "s|api.<CLUSTER_FQDN>|$HOST_CLUSTER_API|g" "$GENERATED_DIR/nfd-cr-template.yaml"
    sed -i "s|image: quay.io/yshnaidm/node-feature-discovery:dpf|image: $NFD_OPERAND_IMAGE|g" "$GENERATED_DIR/nfd-cr-template.yaml"

    # Apply the NFD CR
    KUBECONFIG=$KUBECONFIG oc apply -f "$GENERATED_DIR/nfd-cr-template.yaml"

    log [INFO] "NFD deployment completed successfully!"
}

function apply_crds() {
    log [INFO] "Applying CRDs..."
    for file in "$GENERATED_DIR"/*-crd.yaml; do
        [ -f "$file" ] && apply_manifest "$file"
    done
}

function apply_scc() {
    local scc_file="$GENERATED_DIR/scc.yaml"
    if [ -f "$scc_file" ]; then
        log [INFO] "Applying SCC..."
        apply_manifest "$scc_file"
        sleep 5
    fi
}

function apply_namespaces() {
    log [INFO] "Applying namespaces..."
    for file in "$GENERATED_DIR"/*-ns.yaml; do
        if [ -f "$file" ]; then
            local namespace=$(grep -m 1 "name:" "$file" | awk '{print $2}')
            if [ -z "$namespace" ]; then
                log [ERROR] "Failed to extract namespace from $file"
                return 1
            fi
            if check_namespace_exists "$namespace"; then
                log [INFO] "Skipping namespace $namespace creation"
            else
                apply_manifest "$file"
            fi
        fi
    done
}

function deploy_cert_manager() {
    local cert_manager_file="$GENERATED_DIR/openshift-cert-manager.yaml"
    if [ -f "$cert_manager_file" ]; then
        # Check if cert-manager is already installed
        if oc get deployment -n cert-manager cert-manager &>/dev/null; then
            log [INFO] "Cert-manager already installed. Skipping deployment."
            return 0
        fi
        
        log [INFO] "Deploying cert-manager..."
        apply_manifest "$cert_manager_file"
        
        # Wait for cert-manager namespace to be created by the operator
        log [INFO] "Waiting for cert-manager namespace to be created..."
        local retries=30
        while [ $retries -gt 0 ]; do
            if oc get namespace cert-manager &>/dev/null; then
                log [INFO] "cert-manager namespace found"
                break
            fi
            sleep 5
            retries=$((retries-1))
        done
        
        # Verify namespace was actually created
        if [ $retries -eq 0 ]; then
            log [ERROR] "Timeout: cert-manager namespace was not created after 150 seconds"
            return 1
        fi
        
        # Wait for webhook pod in cert-manager namespace
        wait_for_pods "cert-manager" "app.kubernetes.io/component=webhook" "status.phase=Running" "1/1" 30 5
        log [INFO] "Waiting for cert-manager to stabilize..."
        sleep 5
    fi
}

function deploy_hosted_cluster() {
    deploy_hypershift
}

function deploy_hypershift() {
    # Check if Hypershift operator is already installed
    if oc get deployment -n hypershift hypershift-operator &>/dev/null; then
        log [INFO] "Hypershift operator already installed. Skipping deployment."
    else
        log [INFO] "Installing latest hypershift operator"
        install_hypershift
    fi

    log [INFO] "Checking if Hypershift hosted cluster ${HOSTED_CLUSTER_NAME} already exists..."
    if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
        log [INFO] "Hypershift hosted cluster ${HOSTED_CLUSTER_NAME} already exists. Skipping creation."
    else
        wait_for_pods "hypershift" "app=operator" "status.phase=Running" "1/1" 30 5
        log [INFO] "Creating Hypershift hosted cluster ${HOSTED_CLUSTER_NAME}..."
        oc create ns "${HOSTED_CONTROL_PLANE_NAMESPACE}" || true
        # --network-type=Other \
        hypershift create cluster none --name="${HOSTED_CLUSTER_NAME}" \
          --base-domain="${BASE_DOMAIN}" \
          --release-image="${OCP_RELEASE_IMAGE}" \
          --ssh-key="${SSH_KEY}" \
          --network-type=Other \
          --etcd-storage-class="${ETCD_STORAGE_CLASS}" \
          --node-selector='node-role.kubernetes.io/master=""' \
          --node-upgrade-type=Replace \
          --disable-cluster-capabilities=ImageRegistry \
          --pull-secret="${OPENSHIFT_PULL_SECRET}"
    fi

    log [INFO] "Checking hosted control plane pods..."
    oc -n ${HOSTED_CONTROL_PLANE_NAMESPACE} get pods
    log [INFO] "Waiting for etcd pods..."
    wait_for_pods ${HOSTED_CONTROL_PLANE_NAMESPACE} "app=etcd" "status.phase=Running" "3/3" 60 10

    log [INFO] "Patching nodepool to replica 0..."
    oc patch nodepool -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} --type=merge -p '{"spec":{"replicas":0}}'

    configure_hypershift
    create_ignition_template
}

function create_ignition_template() {
    log [INFO] "Creating ignition template..."
    retry 10 40 "$(dirname "${BASH_SOURCE[0]}")/gen_template.py" -f "${GENERATED_DIR}/hcp_template.yaml" -c "${HOSTED_CLUSTER_NAME}" -hc "${CLUSTERS_NAMESPACE}"
    log [INFO] "Ignition template created"
    oc apply -f "$GENERATED_DIR/hcp_template.yaml"
}

function configure_hypershift() {
    log [INFO] "Creating kubeconfig for Hypershift hosted cluster..."

    if oc get secret -n dpf-operator-system "${HOSTED_CLUSTER_NAME}-admin-kubeconfig" &>/dev/null; then
        log [INFO] "Secret ${HOSTED_CLUSTER_NAME}-admin-kubeconfig already exists. Skipping creation."
    else
      # Wait for the HostedCluster resource to create the admin-kubeconfig secret with valid data
          wait_for_secret_with_data "${CLUSTERS_NAMESPACE}" "${HOSTED_CLUSTER_NAME}-admin-kubeconfig" "kubeconfig" 60 10

          # Then create the kubeconfig with retries
          log [INFO] "Generating kubeconfig file for ${HOSTED_CLUSTER_NAME}..."
          local max_attempts=5
          local delay=10
          # Use retry to generate a valid kubeconfig file
          retry "$max_attempts" "$delay" bash -c '
              ns="$1"; name="$2"
              hypershift create kubeconfig --namespace "$ns" --name "$name" > "$name.kubeconfig" && \
              grep -q "apiVersion: v1" "$name.kubeconfig" && \
              grep -q "kind: Config" "$name.kubeconfig"
          ' _ "${CLUSTERS_NAMESPACE}" "${HOSTED_CLUSTER_NAME}"

    fi

    copy_hypershift_kubeconfig
}

function copy_hypershift_kubeconfig() {
    log [INFO] "Copying hypershift kubeconfig..."
    
    # Extract kubeconfig from secret
    if ! oc get secret -n "${CLUSTERS_NAMESPACE}" "${HOSTED_CLUSTER_NAME}-admin-kubeconfig" -o jsonpath='{.data.kubeconfig}' | base64 -d > ${HOSTED_CLUSTER_NAME}.kubeconfig; then
        log [ERROR] "Failed to extract kubeconfig from secret"
        return 1
    fi
    
    # Verify kubeconfig is not empty
    if [ ! -s "${HOSTED_CLUSTER_NAME}.kubeconfig" ]; then
        log [ERROR] "Extracted kubeconfig is empty"
        return 1
    fi
    
    # Create or update secret in dpf-operator-system namespace
    if ! oc create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig -n dpf-operator-system \
         --from-file=admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque 2>/dev/null; then
        log [INFO] "Secret already exists, updating..."
        if ! oc -n dpf-operator-system create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig \
             --from-file=admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque --dry-run=client -o yaml | oc apply -f -; then
            log [ERROR] "Failed to update kubeconfig secret"
            return 1
        fi
    fi
    
    log [INFO] "Hypershift kubeconfig copied successfully"
}

function apply_remaining() {
    log [INFO] "Applying remaining manifests..."
    for file in "$GENERATED_DIR"/*.yaml; do
        # Skip NFD deployment if DISABLE_NFD is set to true
        if [[ "${DISABLE_NFD}" = "true" && "$file" =~ .*dpf-nfd\.yaml$ ]]; then
            log [INFO] "Skipping NFD deployment (DISABLE_NFD explicitly set to true)"
            continue
        fi

        if [[ ! "$file" =~ .*(-ns)\.yaml$ && \
              ! "$file" =~ .*(-crd)\.yaml$ && \
              "$file" != "$GENERATED_DIR/cert-manager-manifests.yaml" && \
              "$file" != "$GENERATED_DIR/scc.yaml" ]]; then
            retry 5 30 apply_manifest "$file" true
            if [[ "$file" =~ .*operator.*\.yaml$ ]]; then
                log [INFO] "Waiting for operator resources..."
                sleep 10
            fi
        fi
    done
}

function apply_dpf() {
    log "INFO" "Starting DPF deployment sequence..."
    log "INFO" "Provided kubeconfig ${KUBECONFIG}"
    log "INFO" "NFD deployment is $([ "${DISABLE_NFD}" = "true" ] && echo "disabled" || echo "enabled")"
    
    get_kubeconfig
    
    deploy_nfd
    
    apply_namespaces
    apply_crds
    deploy_cert_manager
    
    # Install/upgrade DPF Operator using helm (idempotent operation)
    log "INFO" "Installing/upgrading DPF Operator to $DPF_VERSION..."
    
    # Validate DPF_VERSION is set
    if [ -z "$DPF_VERSION" ]; then
        log "ERROR" "DPF_VERSION is not set. Please set it in env.sh or as environment variable"
        return 1
    fi
    
    # Validate required DPF_PULL_SECRET exists
    if [ ! -f "$DPF_PULL_SECRET" ]; then
        log "ERROR" "DPF_PULL_SECRET file not found: $DPF_PULL_SECRET"
        log "ERROR" "Please ensure the pull secret file exists and contains valid NGC credentials"
        return 1
    fi
    
    # Authenticate helm with NGC registry using pull secret
    NGC_USERNAME=$(jq -r '.auths."nvcr.io".username // empty' "$DPF_PULL_SECRET" 2>/dev/null)
    NGC_PASSWORD=$(jq -r '.auths."nvcr.io".password // empty' "$DPF_PULL_SECRET" 2>/dev/null)
    
    # Validate credentials were extracted (check for empty or 'null' string)
    if [ -z "$NGC_USERNAME" ] || [ -z "$NGC_PASSWORD" ] || [ "$NGC_USERNAME" = "null" ] || [ "$NGC_PASSWORD" = "null" ]; then
        log "ERROR" "Failed to extract NGC credentials from pull secret. Please check the file format."
        return 1
    fi
    log "INFO" "Authenticating helm with NGC registry..."
    # Use stdin to avoid password in process list
    echo "$NGC_PASSWORD" | helm registry login nvcr.io --username "$NGC_USERNAME" --password-stdin >/dev/null 2>&1 || {
        log "ERROR" "Failed to authenticate with NGC registry. Please check your pull secret credentials."
        return 1
    }
    
    # Construct the full chart URL with version
    CHART_URL="${DPF_HELM_REPO_URL}-${DPF_VERSION}.tgz"
    
    # Install without --wait for immediate feedback
    if helm upgrade --install dpf-operator \
        "${CHART_URL}" \
        --namespace dpf-operator-system \
        --create-namespace \
        --values "${HELM_CHARTS_DIR}/dpf-operator-values.yaml"; then
        
        log "INFO" "Helm release 'dpf-operator' deployed successfully"
        log "INFO" "DPF Operator deployment initiated. Use 'oc get pods -n dpf-operator-system' to monitor progress."
    else
        log "ERROR" "Helm deployment failed"
        return 1
    fi
    
    apply_remaining
    apply_scc
    deploy_hosted_cluster

    wait_for_pods "dpf-operator-system" "dpu.nvidia.com/component=dpf-operator-controller-manager" "status.phase=Running" "1/1" 30 5

    log [INFO] "DPF deployment complete"
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    log [INFO] "Executing command: $command"
    case "$command" in
            deploy-nfd)
                deploy_nfd
                ;;
            apply-dpf)
                apply_dpf
                ;;
            deploy-hypershift)
                deploy_hypershift
                ;;
            create-ignition-template)
                create_ignition_template
                ;;
            copy_hypershift_kubeconfig)
                copy_hypershift_kubeconfig
                ;;
            *)
                log [INFO] "Unknown command: $command"
                log [INFO] "Available commands: deploy-nfd, apply-dpf, deploy-hypershift"
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
