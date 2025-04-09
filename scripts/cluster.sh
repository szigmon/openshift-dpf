#!/bin/bash
# cluster.sh - Cluster management operations

# Exit on error
set -e

# Source environment variables
source "$(dirname "$0")/env.sh"

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# -----------------------------------------------------------------------------
# Cluster management functions
# -----------------------------------------------------------------------------
function check_create_cluster() {
    log "Checking for cluster: ${CLUSTER_NAME}"
    
    # Convert single VIPs to lists
    if [ -n "$API_VIP" ]; then
        API_VIPS="['$API_VIP']"
    else
        API_VIPS="['']"
    fi

    if [ -n "$INGRESS_VIP" ]; then
        INGRESS_VIPS="['$INGRESS_VIP']"
    else
        INGRESS_VIPS="['']"
    fi

    # Check if cluster exists
    if ! aicli list clusters | grep -q "$CLUSTER_NAME"; then
        log "Cluster '$CLUSTER_NAME' not found. Creating..."
        
        # Create cluster based on VM_COUNT
        if [ "$VM_COUNT" -eq 1 ]; then
            log "Detected VM_COUNT=1; creating a Single-Node OpenShift (SNO) cluster."
            aicli create cluster \
                -P openshift_version=$OPENSHIFT_VERSION \
                -P base_dns_domain=$BASE_DOMAIN \
                -P pull_secret=$OPENSHIFT_PULL_SECRET \
                -P high_availability_mode=None \
                -P user_managed_networking=True \
                $CLUSTER_NAME
        else
            aicli create cluster \
                -P openshift_version=$OPENSHIFT_VERSION \
                -P base_dns_domain=$BASE_DOMAIN \
                -P api_vips=$API_VIPS \
                -P pull_secret=$OPENSHIFT_PULL_SECRET \
                -P ingress_vips=$INGRESS_VIPS \
                $CLUSTER_NAME
        fi
    else
        log "Using existing cluster: $CLUSTER_NAME"
    fi
}

function delete_cluster() {
    log "Deleting cluster $CLUSTER_NAME..."
    aicli delete cluster $CLUSTER_NAME -y || true
}

function wait_for_cluster_status() {
    local target_status=$1
    local max_retries=${2:-$MAX_RETRIES}
    local sleep_time=${3:-$SLEEP_TIME}
    
    log "Waiting for cluster $CLUSTER_NAME to reach status: $target_status"
    local retries=0

    while [ $retries -lt $max_retries ]; do
        local current_status=$(aicli info cluster "$CLUSTER_NAME" -f status -v)
        log "Current status: $current_status"

        if [ "$current_status" = "$target_status" ]; then
            log "Cluster $CLUSTER_NAME has reached status: $target_status"
            return 0
        fi

        log "Attempt $retries of $max_retries. Waiting $sleep_time seconds..."
        sleep $sleep_time
        ((retries++))
    done

    log "Timeout waiting for cluster to reach status: $target_status"
    return 1
}

function start_cluster_installation() {
    log "Starting installation of cluster $CLUSTER_NAME"
    aicli start cluster "$CLUSTER_NAME"
}

function cluster_install() {
    wait_for_cluster_status "ready"
    start_cluster_installation
    wait_for_cluster_status "installed"
    log "Cluster installation completed successfully!"
}

function get_kubeconfig() {
    log "Managing kubeconfig..."
    
    if [ ! -f "$KUBECONFIG" ]; then
        log "Downloading kubeconfig for $CLUSTER_NAME"
        aicli download kubeconfig "$CLUSTER_NAME"
        log "Kubeconfig downloaded to $KUBECONFIG"
    else
        log "Using existing kubeconfig at: $KUBECONFIG"
    fi

    # Set KUBECONFIG environment variable
    export KUBECONFIG="$(pwd)/$KUBECONFIG"
    log "KUBECONFIG is set to: $KUBECONFIG"
}

function clean_all() {
    log "Performing full cleanup of cluster and VMs..."
    
    # Delete the cluster
    delete_cluster
    
    # Delete VMs
    log "Deleting VMs with prefix $VM_PREFIX..."
    env VM_PREFIX="$VM_PREFIX" scripts/delete_vms.sh || true
    
    # Clean resources
    clean_resources
    
    log "Full cleanup complete"
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    case "$command" in
        check-create-cluster)
            check_create_cluster
            ;;
        delete-cluster)
            delete_cluster
            ;;
        cluster-install)
            cluster_install
            ;;
        wait-for-status)
            wait_for_cluster_status "$1"
            ;;
        get-kubeconfig)
            get_kubeconfig
            ;;
        clean-all)
            clean_all
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: check-create-cluster, delete-cluster, cluster-install,"
            log "  wait-for-status, get-kubeconfig, clean-all"
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