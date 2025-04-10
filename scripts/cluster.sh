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
    log "INFO" "Checking if cluster ${CLUSTER_NAME} exists..."
    
    if ! aicli get cluster ${CLUSTER_NAME} >/dev/null 2>&1; then
        log "INFO" "Cluster ${CLUSTER_NAME} not found, creating..."
        
        if [ "${SINGLE_NODE}" = "true" ]; then
            log "INFO" "Creating single-node cluster..."
            aicli create cluster ${CLUSTER_NAME} \
                --base-domain ${BASE_DOMAIN} \
                --pull-secret ${PULL_SECRET} \
                --ssh-key ${SSH_KEY} \
                --single-node
        else
            log "INFO" "Creating multi-node cluster..."
            aicli create cluster ${CLUSTER_NAME} \
                --base-domain ${BASE_DOMAIN} \
                --pull-secret ${PULL_SECRET} \
                --ssh-key ${SSH_KEY} \
                --workers ${NUM_WORKERS}
        fi
        
        log "INFO" "Cluster ${CLUSTER_NAME} created successfully"
    else
        log "INFO" "Cluster ${CLUSTER_NAME} already exists"
    fi
}

function delete_cluster() {
    log "INFO" "Deleting cluster ${CLUSTER_NAME}..."
    aicli delete cluster ${CLUSTER_NAME} -y
    log "INFO" "Cluster ${CLUSTER_NAME} deleted successfully"
}

function wait_for_cluster_status() {
    local status=$1
    local max_retries=${2:-60}
    local sleep_time=${3:-10}
    local retries=0
    
    log "INFO" "Waiting for cluster ${CLUSTER_NAME} to reach status: ${status}"
    
    while [ $retries -lt $max_retries ]; do
        if aicli get cluster ${CLUSTER_NAME} -o jsonpath='{.status}' | grep -q "^${status}$"; then
            log "INFO" "Cluster ${CLUSTER_NAME} reached status: ${status}"
            return 0
        fi
        log "DEBUG" "Current status: $(aicli get cluster ${CLUSTER_NAME} -o jsonpath='{.status}')"
        log "INFO" "Waiting for status ${status}... (attempt $((retries + 1))/${max_retries})"
        sleep $sleep_time
        retries=$((retries + 1))
    done
    
    log "ERROR" "Timeout waiting for cluster ${CLUSTER_NAME} to reach status: ${status}"
    return 1
}

function start_cluster_installation() {
    log "INFO" "Starting installation for cluster ${CLUSTER_NAME}..."
    
    aicli start cluster ${CLUSTER_NAME}
    log "INFO" "Waiting for cluster to be ready..."
    wait_for_cluster_status "ready"
    log "INFO" "Waiting for installation to complete..."
    wait_for_cluster_status "installed"
    log "INFO" "Cluster installation completed successfully"
}

function get_kubeconfig() {
    log "INFO" "Getting kubeconfig..."
    
    # Determine the kubeconfig path (from environment or env.sh)
    local kubeconfig_path="${KUBECONFIG:-}"
    
    if [ -z "${kubeconfig_path}" ]; then
        log "INFO" "KUBECONFIG not set in environment, checking env.sh..."
        source "$(dirname "$0")/env.sh"
        kubeconfig_path="${KUBECONFIG:-}"
    fi

    # Trim leading and trailing whitespace
    kubeconfig_path="${kubeconfig_path#"${kubeconfig_path%%[![:space:]]*}"}"  # Trim leading spaces
    kubeconfig_path="${kubeconfig_path%"${kubeconfig_path##*[![:space:]]}"}"  # Trim trailing spaces

    # Validate the kubeconfig path
    if [ -n "${kubeconfig_path}" ] && [ -f "${kubeconfig_path}" ] && [ -r "${kubeconfig_path}" ]; then
        log "INFO" "Using KUBECONFIG: ${kubeconfig_path}"
        export KUBECONFIG="${kubeconfig_path}"
        return 0
    else
        log "ERROR" "KUBECONFIG file not found or inaccessible: ${kubeconfig_path}"
        exit 1
    fi
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
            start_cluster_installation
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