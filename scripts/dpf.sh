#!/bin/bash
# dpf.sh - DPF deployment operations

# Exit on error
set -e

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
    
    # Check if NFD should be disabled
    if [ "$DISABLE_NFD" = "true" ]; then
        log [INFO] "NFD deployment is disabled (DISABLE_NFD=true). Skipping..."
        return 0
    fi

    # Check if NFD operator is already installed
    if oc get deployment -n openshift-nfd nfd-operator &>/dev/null; then
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
    make -C cluster-nfd-operator deploy IMAGE_TAG=$NFD_OPERATOR_IMAGE KUBECONFIG=$KUBECONFIG

    log [INFO] "NFD operator deployment from source completed"

    # Create NFD instance with custom operand image
    log [INFO] "Creating NFD instance with custom operand image..."
    mkdir -p "$GENERATED_DIR"
    cp "$MANIFESTS_DIR/dpf-installation/nfd-cr-template.yaml" "$GENERATED_DIR/nfd-cr-template.yaml"
    echo
    sed -i "s|api.CLUSTER_FQDN|$HOST_CLUSTER_API|g" "$GENERATED_DIR/nfd-cr-template.yaml"
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
            if check_namespace_exists "$namespace"; then
                log [INFO] "Skipping namespace $namespace creation"
            else
                apply_manifest "$file"
            fi
        fi
    done
}

function deploy_cert_manager() {
    local cert_manager_file="$GENERATED_DIR/cert-manager-manifests.yaml"
    if [ -f "$cert_manager_file" ]; then
        # Check if cert-manager is already installed
        if oc get deployment -n cert-manager cert-manager-operator &>/dev/null; then
            log [INFO] "Cert-manager already installed. Skipping deployment."
            return 0
        fi
        
        log [INFO] "Deploying cert-manager..."
        apply_manifest "$cert_manager_file"
        wait_for_pods "cert-manager-operator" "app=webhook" "status.phase=Running" "1/1" 30 5
        log [INFO] "Waiting for cert-manager to stabilize..."
        sleep 5
    fi
}

function deploy_hosted_cluster() {
    if [ "${DPF_CLUSTER_TYPE}" = "kamaji" ]; then
        deploy_kamaji
    else
        deploy_hypershift
    fi
}

function deploy_kamaji() {
    log [INFO] "Deploying kamaji..."
    apply_manifest "$GENERATED_DIR/kamaji-manifests.yaml"
    log [INFO] "Waiting for etcd pods..."
    wait_for_pods "dpf-operator-system" "application=kamaji-etcd" "status.phase=Running" "1/1" 60 10
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
    retry 5 30 "$(dirname "${BASH_SOURCE[0]}")/gen_template.py" -f "${GENERATED_DIR}/hcp_template.yaml" -c "${HOSTED_CLUSTER_NAME}" -hc "${CLUSTERS_NAMESPACE}"
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
    

    # Create the admin kubeconfig secret
    oc create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig -n dpf-operator-system \
      --from-file=admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque || \
      oc -n dpf-operator-system create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig \
      --from-file=admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque --dry-run=client -o yaml | oc apply -f -
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
              "$file" != "$GENERATED_DIR/kamaji-manifests.yaml" && \
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
    
    # Check if prepare-dpf-manifests.sh exists
    local prepare_script="$(dirname "${BASH_SOURCE[0]}")/prepare-dpf-manifests.sh"
    if [ ! -f "$prepare_script" ]; then
        log [INFO] "Error: $prepare_script not found"
        exit 1
    fi
    
    # Call the prepare-dpf-manifests.sh script directly
    "$prepare_script"
    
    get_kubeconfig
    deploy_nfd
    
    apply_namespaces
    apply_crds
    deploy_cert_manager
    apply_remaining
    apply_scc
    deploy_hosted_cluster
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