#!/bin/bash

GENERATED_DIR=${GENERATED_DIR:-"manifests/generated/"}
KUBECONFIG=${KUBECONFIG}
DPF_CLUSTER_TYPE=${DPF_CLUSTER_TYPE:-"hypershift"}
DISABLE_NFD=${DISABLE_NFD:-"false"}  # New environment variable to disable NFD deployment

function log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

function apply_manifest() {
    local file=$1
    echo "Applying $file..."
    oc apply -f "$file"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Failed to apply $file (exit code: $exit_code)"
        return $exit_code
    fi
    return 0
}

function wait_for_pods() {
    local namespace=$1
    local label=$2
    local selector=$3
    local expected_state=$4
    local max_attempts=$5
    local delay=$6

    for i in $(seq 1 "$max_attempts"); do
        oc get pods -n "$namespace" -l "$label" --field-selector "$selector"
        if oc get pods -n "$namespace" -l "$label" --field-selector "$selector" 2>/dev/null | grep -q "$expected_state"; then
            log "$label pods are ready"
            return 0
        fi
        log "Waiting for $label pods (attempt $i/$max_attempts)..."
        sleep "$delay"
    done

    log "$label pods failed to become ready"
    oc get pods -n "$namespace"
    oc describe pod -n "$namespace" -l "$label"
    exit 1
}

function wait_for_resource() {
    local namespace=$1
    local resource_type=$2
    local resource_name=$3
    local max_attempts=${4:-30}
    local delay=${5:-5}

    log "Waiting for $resource_type/$resource_name in namespace $namespace..."

    for i in $(seq 1 "$max_attempts"); do
        if oc get "$resource_type" -n "$namespace" "$resource_name" &>/dev/null; then
            log "$resource_type/$resource_name found in namespace $namespace"
            return 0
        fi
        log "Waiting for $resource_type/$resource_name (attempt $i/$max_attempts)..."
        sleep "$delay"
    done

    log "Timed out waiting for $resource_type/$resource_name in namespace $namespace"
    return 1
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

log "Starting deployment sequence..."
echo "Provided kubeconfig ${KUBECONFIG}"
echo "NFD deployment is $([ "${DISABLE_NFD}" = "true" ] && echo "disabled" || echo "enabled")"
apply_namespaces
apply_crds
deploy_cert_manager
apply_remaining
apply_scc
deploy_hosted_cluster
log "Deployment complete"