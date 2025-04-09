#!/bin/bash
# dpf.sh - DPF deployment operations

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# -----------------------------------------------------------------------------
# DPF deployment functions
# -----------------------------------------------------------------------------
function deploy_nfd() {
    log "Managing NFD deployment..."
    
    # Check if NFD should be disabled
    if [ "$DISABLE_NFD" = "true" ]; then
        log "NFD deployment is disabled (DISABLE_NFD=true). Skipping..."
        return 0
    fi

    log "Deploying NFD operator directly from source..."

    # Check if Go is installed
    if ! command -v go &> /dev/null; then
        log "Error: Go is not installed but required for NFD operator deployment"
        log "Please install Go before continuing"
        exit 1
    fi

    # Clone the NFD operator repository if not exists
    if [ ! -d "cluster-nfd-operator" ]; then
        log "NFD operator repository not found. Cloning..."
        git clone https://github.com/openshift/cluster-nfd-operator.git
    fi

    # Deploy the NFD operator
    make -C cluster-nfd-operator deploy IMAGE_TAG=$NFD_OPERATOR_IMAGE KUBECONFIG=$KUBECONFIG

    log "NFD operator deployment from source completed"

    # Create NFD instance with custom operand image
    log "Creating NFD instance with custom operand image..."
    mkdir -p "$GENERATED_DIR"
    cp "$MANIFESTS_DIR/dpf-installation/nfd-cr-template.yaml" "$GENERATED_DIR/nfd-cr.yaml"
    sed -i "s|api.CLUSTER_FQDN|$HOST_CLUSTER_API|g" "$GENERATED_DIR/nfd-cr.yaml"
    sed -i "s|image: quay.io/yshnaidm/node-feature-discovery:dpf|image: $NFD_OPERAND_IMAGE|g" "$GENERATED_DIR/nfd-cr.yaml"

    # Apply the NFD CR
    KUBECONFIG=$KUBECONFIG oc apply -f "$GENERATED_DIR/nfd-cr.yaml"

    log "NFD deployment completed successfully!"
}

function apply_crds() {
    log "Applying CRDs..."
    for file in "$GENERATED_DIR"/*-crd.yaml; do
        [ -f "$file" ] && apply_manifest "$file"
    done
}

function apply_scc() {
    local scc_file="$GENERATED_DIR/scc.yaml"
    if [ -f "$scc_file" ]; then
        log "Applying SCC..."
        apply_manifest "$scc_file"
        sleep 5
    fi
}

function apply_namespaces() {
    log "Applying namespaces..."
    for file in "$GENERATED_DIR"/*-ns.yaml; do
        [ -f "$file" ] && apply_manifest "$file"
    done
}

function deploy_cert_manager() {
    local cert_manager_file="$GENERATED_DIR/cert-manager-manifests.yaml"
    if [ -f "$cert_manager_file" ]; then
        log "Deploying cert-manager..."
        apply_manifest "$cert_manager_file"
        wait_for_pods "cert-manager-operator" "app=webhook" "status.phase=Running" "1/1" 30 5
        log "Waiting for cert-manager to stabilize..."
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
    log "Deploying kamaji..."
    apply_manifest "$GENERATED_DIR/kamaji-manifests.yaml"
    log "Waiting for etcd pods..."
    wait_for_pods "dpf-operator-system" "application=kamaji-etcd" "status.phase=Running" "1/1" 60 10
}

function deploy_hypershift() {
    log "Waiting for hypershift operator"
    wait_for_pods "hypershift" "app=operator" "status.phase=Running" "1/1" 30 5
    log "Creating Hypershift hosted cluster ${HOSTED_CLUSTER_NAME}..."
    oc create ns "${HOSTED_CONTROL_PLANE_NAMESPACE}" || true
    hypershift create cluster none --name=${HOSTED_CLUSTER_NAME} \
      --base-domain=${BASE_DOMAIN} \
      --release-image="${OCP_RELEASE_IMAGE}" \
      --ssh-key=${HOME}/.ssh/id_rsa.pub \
      --network-type=Other \
      --etcd-storage-class=${ETCD_STORAGE_CLASS} \
      --pull-secret=${OPENSHIFT_PULL_SECRET}

    log "Checking hosted control plane pods..."
    oc -n ${HOSTED_CONTROL_PLANE_NAMESPACE} get pods
    log "Waiting for etcd pods..."
    wait_for_pods ${HOSTED_CONTROL_PLANE_NAMESPACE} "app=etcd" "status.phase=Running" "3/3" 60 10

    log "Pausing nodepool to disable rhcos update..."
    oc patch nodepool -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} --type=merge -p '{"spec":{"pausedUntil":"true"}}'

    configure_hypershift
}

function configure_hypershift() {
    log "Creating kubeconfig for Hypershift hosted cluster..."

    # Wait for the HostedCluster resource to be created before proceeding
    wait_for_resource "${CLUSTERS_NAMESPACE}" "secret" "${HOSTED_CLUSTER_NAME}-admin-kubeconfig" 60 10

    # Then create the kubeconfig
    hypershift create kubeconfig --namespace ${CLUSTERS_NAMESPACE} --name ${HOSTED_CLUSTER_NAME} > ${HOSTED_CLUSTER_NAME}.kubeconfig

    # Create the admin kubeconfig secret
    oc create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig -n dpf-operator-system \
      --from-file=admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque || \
      oc -n dpf-operator-system create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig \
      --from-file=admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig --type=Opaque --dry-run=client -o yaml | oc apply -f -
}

function apply_remaining() {
    log "Applying remaining manifests..."
    for file in "$GENERATED_DIR"/*.yaml; do
        # Skip NFD deployment if DISABLE_NFD is set to true
        if [[ "${DISABLE_NFD}" = "true" && "$file" =~ .*dpf-nfd\.yaml$ ]]; then
            log "Skipping NFD deployment (DISABLE_NFD explicitly set to true)"
            continue
        fi

        if [[ ! "$file" =~ .*(-ns)\.yaml$ && \
              "$file" != "$GENERATED_DIR/cert-manager-manifests.yaml" && \
              "$file" != "$GENERATED_DIR/kamaji-manifests.yaml" && \
              "$file" != "$GENERATED_DIR/scc.yaml" ]]; then
            apply_manifest "$file"
            if [[ "$file" =~ .*operator.*\.yaml$ ]]; then
                log "Waiting for operator resources..."
                sleep 10
            fi
        fi
    done
}

function apply_dpf() {
    log "Starting DPF deployment sequence..."
    log "Provided kubeconfig ${KUBECONFIG}"
    log "NFD deployment is $([ "${DISABLE_NFD}" = "true" ] && echo "disabled" || echo "enabled")"
    
    prepare_dpf_manifests
    get_kubeconfig
    install_hypershift
    deploy_nfd
    
    apply_namespaces
    apply_crds
    deploy_cert_manager
    apply_remaining
    apply_scc
    deploy_hosted_cluster
    
    log "DPF deployment complete"
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    case "$command" in
        deploy-nfd)
            deploy_nfd
            ;;
        apply-dpf)
            apply_dpf
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: deploy-nfd, apply-dpf"
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