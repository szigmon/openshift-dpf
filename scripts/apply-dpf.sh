#!/bin/bash

GENERATED_DIR=${GENERATED_DIR:-"manifests/generated/"}
KUBECONFIG=${KUBECONFIG}
DISABLE_KAMAJI=${DISABLE_KAMAJI:-"false"}
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

function deploy_kamaji() {
    if [ "${DISABLE_KAMAJI}" = "false" ]; then
        log "Deploying kamaji..."
        apply_manifest "$GENERATED_DIR/kamaji-manifests.yaml"
        log "Waiting for etcd pods..."
        wait_for_pods "dpf-operator-system" "application=kamaji-etcd" "status.phase=Running" "1/1" 60 10
    else
        log "Skipping kamaji deployment (DISABLE_KAMAJI explicitly set to true)"
    fi
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
deploy_kamaji
log "Deployment complete"