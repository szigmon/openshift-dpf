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

    if [ "${NFD_DEPLOY_FROM_GIT}" = "true" ]; then

        # Ensure namespace exists
        oc get ns "${NFD_NAMESPACE}" >/dev/null 2>&1 || oc create ns "${NFD_NAMESPACE}"

            # Check if NFD operator is already installed
        if oc get deployment -n ${NFD_NAMESPACE} nfd-operator &>/dev/null; then
            log [INFO] "NFD operator already installed. Skipping deployment."
            return 0
        fi

        log [INFO] "Deploying NFD operator directly from source..."

        # Check if Go is installed
        if ! command -v go &> /dev/null; then
            log [INFO] "Error: Go is not installed but required for NFD operator deployment"
            log [INFO] "Please install Go before continuing"
            exit 1
        fi

        # Clone the NFD operator repository if not exists
        if [ ! -d "cluster-nfd-operator" ]; then
            log [INFO] "NFD operator repository not found. Cloning..."
            git clone https://github.com/openshift/cluster-nfd-operator.git
        fi
        get_kubeconfig

        # Deploy the NFD operator
        if ! make -C cluster-nfd-operator deploy deploy IMAGE_TAG=$NFD_OPERATOR_IMAGE KUBECONFIG=$KUBECONFIG; then
            log [ERROR] "Failed to deploy NFD operator"
            return 1
        fi

        # Ensure CRD is ready before creating the CR instance
        log [INFO] "Waiting for NodeFeatureDiscovery CRD to be established..."
        oc wait --for=condition=Established crd/nodefeaturediscoveries.nfd.openshift.io --timeout=180s || true

        # Create NFD CR instance (inject operand image only when running from git)
        log [INFO] "Creating NFD instance via CR..."
        mkdir -p "$GENERATED_DIR"
        cp "$MANIFESTS_DIR/dpf-installation/nfd-cr-template.yaml" "$GENERATED_DIR/nfd-cr-template.yaml"
        sed -i "s|api.<CLUSTER_FQDN>|$HOST_CLUSTER_API|g" "$GENERATED_DIR/nfd-cr-template.yaml"

        if [ -n "${NFD_OPERAND_IMAGE}" ]; then
            log [INFO] "Setting operand image in NFD CR to ${NFD_OPERAND_IMAGE}"
            # Insert the image field directly under the operand: key with proper indentation
            awk -v img="${NFD_OPERAND_IMAGE}" '
                {
                    print
                    if ($0 ~ /^\s{2}operand:\s*$/ && !inserted) {
                        print "    image: " img
                        inserted=1
                    }
                }
            ' "$GENERATED_DIR/nfd-cr-template.yaml" > "$GENERATED_DIR/nfd-cr.yaml.tmp" && mv "$GENERATED_DIR/nfd-cr.yaml.tmp" "$GENERATED_DIR/nfd-cr-template.yaml"
        fi

        # Wait for components to be ready
        wait_for_pods "${NFD_NAMESPACE}" "app=nfd-worker" "status.phase=Running" "1/1" 30 10 || true

        log [INFO] "NFD deployment from git completed successfully!"
    else
        # Operator-based flow (default)
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
    
    fi

    log [INFO] "Creating NFD instance..."
    mkdir -p "$GENERATED_DIR"
    cp "$MANIFESTS_DIR/dpf-installation/nfd-cr-template.yaml" "$GENERATED_DIR/nfd-cr-template.yaml"
    echo
    sed -i "s|api.<CLUSTER_FQDN>|$HOST_CLUSTER_API|g" "$GENERATED_DIR/nfd-cr-template.yaml"

    # Apply the NFD CR
    KUBECONFIG=$KUBECONFIG oc apply -f "$GENERATED_DIR/nfd-cr-template.yaml"

    log [INFO] "NFD deployment completed successfully!"
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
    if [ "${ENABLE_HCP_MULTUS}" = "true" ]; then
        log [INFO] "HCP Multus enabled mode is active. Using custom hypershift image: ${HYPERSHIFT_IMAGE}"
    fi
    
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
        
        # Build hypershift command with conditional multi-network flag
        local multi_network_flag=""

        if [ "${ENABLE_HCP_MULTUS}" != "true" ]; then
            multi_network_flag="--disable-multi-network"
        fi

        log [INFO] "Creating hosted cluster with HCP multus enabled ${ENABLE_HCP_MULTUS}..."
        hypershift create cluster none --name="${HOSTED_CLUSTER_NAME}" \
          --base-domain="${BASE_DOMAIN}" \
          --release-image="${OCP_RELEASE_IMAGE}" \
          --ssh-key="${SSH_KEY}" \
          --pull-secret="${OPENSHIFT_PULL_SECRET}" \
          --disable-cluster-capabilities=ImageRegistry,Insights,Console,openshift-samples,Ingress,NodeTuning \
          ${multi_network_flag} \
          --network-type=Other \
          --etcd-storage-class="${ETCD_STORAGE_CLASS}" \
          --node-selector='node-role.kubernetes.io/master=""' \
          --node-upgrade-type=Replace \
          --control-plane-operator-image=quay.io/lhadad/controlplaneoperator:allCapsMultusDisabledV1
    fi

    log [INFO] "Adding CNO image override annotation..."
    local max_retries=10
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if oc annotate hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} \
           hypershift.openshift.io/image-overrides=cluster-network-operator=quay.io/lhadad/cluster-network-operator:ingressJul24v1 \
           --overwrite; then
            log [INFO] "Successfully added CNO image override annotation"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log [WARN] "Failed to annotate hosted cluster (attempt $retry_count/$max_retries), retrying in 5s..."
                sleep 5
            else
                log [ERROR] "Failed to annotate hosted cluster after $max_retries attempts"
            fi
        fi
    done

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
         --from-file=super-admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque 2>/dev/null; then
        log [INFO] "Secret already exists, updating..."
        if ! oc -n dpf-operator-system create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig \
             --from-file=super-admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque --dry-run=client -o yaml | oc apply -f -; then
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

function deploy_argocd() {
    log [INFO] "Deploying ArgoCD..."
    
    # Check if ArgoCD is already installed
    if check_helm_release_exists "dpf-operator-system" "argo-cd"; then
        log [INFO] "Skipping ArgoCD deployment."
        return 0
    fi
    
    # Ensure helm is installed
    ensure_helm_installed
    
    # Add ArgoCD helm repository
    log [INFO] "Adding ArgoCD helm repository..."
    helm repo add argoproj https://argoproj.github.io/argo-helm || true
    helm repo update
    
    # Install ArgoCD
    log [INFO] "Installing ArgoCD chart version ${ARGOCD_CHART_VERSION}..."
    helm upgrade --install argo-cd argoproj/argo-cd \
        --namespace dpf-operator-system \
        --create-namespace \
        --version ${ARGOCD_CHART_VERSION} \
        --values "${HELM_CHARTS_DIR}/argocd-values.yaml" \
        --wait
    
    # Apply SCC permissions for ArgoCD
    log [INFO] "Applying OpenShift SCCs for ArgoCD..."
    apply_manifest "${MANIFESTS_DIR}/dpf-installation/argocd-scc.yaml"
    
    # Restart Redis to pick up SCC
    oc rollout restart deployment/argo-cd-argocd-redis -n dpf-operator-system || true
    
    log [INFO] "ArgoCD deployment complete!"
}

function deploy_maintenance_operator() {
    log [INFO] "Deploying Maintenance Operator..."
    
    # Check if Maintenance Operator is already installed
    if check_helm_release_exists "dpf-operator-system" "maintenance-operator"; then
        log [INFO] "Skipping Maintenance Operator deployment."
        return 0
    fi
    
    # Ensure helm is installed
    ensure_helm_installed
    
    # Install Maintenance Operator
    log [INFO] "Installing Maintenance Operator chart..."
    helm upgrade --install maintenance-operator oci://ghcr.io/mellanox/maintenance-operator-chart \
        --namespace dpf-operator-system \
        --create-namespace \
        --version ${MAINTENANCE_OPERATOR_VERSION} \
        --values "${HELM_CHARTS_DIR}/maintenance-operator-values.yaml" \
        --wait
    
    log [INFO] "Maintenance Operator deployment complete!"
}

function apply_dpf() {
    log "INFO" "Starting DPF deployment sequence..."
    log "INFO" "Provided kubeconfig ${KUBECONFIG}"
    log "INFO" "NFD deployment is $([ "${DISABLE_NFD}" = "true" ] && echo "disabled" || echo "enabled")"
    
    get_kubeconfig
    
    # Verify cluster is accessible before any deployments
    log "INFO" "Verifying cluster accessibility..."
    if ! oc cluster-info &>/dev/null; then
        log "ERROR" "Cluster is not accessible. Cannot proceed with DPF deployment."
        log "ERROR" "Please ensure the cluster is running and accessible."
        log "ERROR" "For SNO: Check if cluster VMs are running with: virsh list --all"
        return 1
    fi
    log "INFO" "Cluster is accessible, proceeding with DPF deployment..."
    
    # Deploy ArgoCD and Maintenance Operator for DPF v25.7+
    if [[ "$DPF_VERSION" =~ ^v25\.[7-9] ]] || [[ "$DPF_VERSION" =~ ^v2[6-9] ]]; then
        log [INFO] "DPF version $DPF_VERSION requires ArgoCD and Maintenance Operator"
        deploy_argocd
        deploy_maintenance_operator
    fi
    
    deploy_nfd
    
    apply_namespaces
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
    
    # Determine chart URL and args based on format
    if [[ "$DPF_HELM_REPO_URL" == oci://* ]]; then
        # OCI registry format (v25.7+)
        CHART_URL="${DPF_HELM_REPO_URL}/dpf-operator"
        HELM_ARGS="--version ${DPF_VERSION}"
    else
        # Legacy NGC format (v25.4 and older)
        CHART_URL="${DPF_HELM_REPO_URL}-${DPF_VERSION}.tgz"
        HELM_ARGS=""
    fi
    
    # Install without --wait for immediate feedback
    if helm upgrade --install dpf-operator \
        "${CHART_URL}" \
        ${HELM_ARGS} \
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
            deploy-argocd)
                deploy_argocd
                ;;
            deploy-maintenance-operator)
                deploy_maintenance_operator
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
                log [INFO] "Available commands: deploy-nfd, deploy-argocd, deploy-maintenance-operator, apply-dpf, deploy-hypershift"
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
