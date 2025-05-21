#!/bin/bash
# cluster.sh - Cluster management operations for OpenShift DPF
#
# This file contains functions for managing OpenShift clusters and ISO images.
# ISO handling is implemented with a minimal, single-function approach:
#   - get_iso: Universal function for master/worker ISO operations (URL or download)
#
# Key features:
# - InfraEnv approach for token-based URLs (required for authentication)
# - Fallback to console.redhat.com UI if direct method fails
# - Special handling for token-based URLs to preserve authentication
# - Support for both minimal and full ISO types

# Exit on error
set -e

# Source environment variables
source "$(dirname "$0")/env.sh"

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

function validate_vips() {
    if [ -z "${API_VIP}" ] || [ "${API_VIP}" = "[]" ]; then
        log "ERROR" "API_VIPS is not set or invalid. Please provide a valid API_VIP."
        exit 1
    fi

    if [ -z "${INGRESS_VIP}" ] || [ "${INGRESS_VIP}" = "[]" ]; then
        log "ERROR" "INGRESS_VIPS is not set or invalid. Please provide a valid INGRESS_VIP."
        exit 1
    fi
    # Validate API_VIP and INGRESS_VIP
    if is_valid_ip "${API_VIP}"; then
        export API_VIPS="[${API_VIP}]"
    else
        log "ERROR" "Invalid API_VIP: ${API_VIP}"
        exit 1
    fi

    # Construct INGRESS_VIPS
    if is_valid_ip "${INGRESS_VIP}"; then
        export INGRESS_VIPS="[${INGRESS_VIP}]"
    else
        log "ERROR" "Invalid INGRESS_VIP: ${INGRESS_VIP}"
        exit 1
    fi
}

function is_valid_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || $ip =~ ^([0-9a-fA-F]*:[0-9a-fA-F]*){2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Cluster management functions
# -----------------------------------------------------------------------------
function check_create_cluster() {
    log "INFO" "Checking if cluster ${CLUSTER_NAME} exists..."
    
    if ! aicli info cluster ${CLUSTER_NAME} >/dev/null 2>&1; then
        log "INFO" "Cluster ${CLUSTER_NAME} not found, creating..."

        if [ "$VM_COUNT" -eq 1 ]; then
            log "INFO" "Creating single-node cluster..."
            aicli create cluster \
                -P openshift_version="${OPENSHIFT_VERSION}" \
                -P base_dns_domain="${BASE_DOMAIN}" \
                -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
                -P high_availability_mode=None \
                -P user_managed_networking=True \
                "${CLUSTER_NAME}"
        else
            log "INFO" "Creating multi-node cluster..."
            validate_vips
            echo "API_VIPS: ${API_VIPS}"
            echo "INGRESS_VIPS: ${INGRESS_VIPS}"
            aicli create cluster \
                -P openshift_version="${OPENSHIFT_VERSION}" \
                -P base_dns_domain="${BASE_DOMAIN}" \
                -P api_vips="${API_VIPS}" \
                -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
                -P public_key="${SSH_KEY}" \
                -P ingress_vips="${INGRESS_VIPS}" \
                "${CLUSTER_NAME}"
        fi
        
        log "INFO" "Cluster ${CLUSTER_NAME} created successfully"
    else
        log "INFO" "Cluster ${CLUSTER_NAME} already exists"
    fi
}

function delete_cluster() {
    log "INFO" "Deleting cluster ${CLUSTER_NAME}..."
    if ! aicli delete cluster ${CLUSTER_NAME} -y; then
        log "WARNING" "Failed to delete cluster ${CLUSTER_NAME}, continuing anyway"
    else
        log "INFO" "Cluster ${CLUSTER_NAME} deleted successfully"
    fi
}

function wait_for_cluster_status() {
    local status=$1
    local max_retries=${2:-120}
    local sleep_time=${3:-60}
    local retries=0
    
    log "INFO" "Waiting for cluster ${CLUSTER_NAME} to reach status: ${status}"
    while [ $retries -lt $max_retries ]; do
        current_status=$(aicli info cluster "$CLUSTER_NAME" -f status -v)
        # If waiting for 'ready' but status is already 'installed', treat as success
        if [ "$status" == "ready" ] && [ "$current_status" == "installed" ]; then
            log "INFO" "Cluster ${CLUSTER_NAME} is already installed. Skipping wait for 'ready'."
            return 0
        fi
        if [ "$current_status" == "$status" ]; then
            log "INFO" "Cluster ${CLUSTER_NAME} reached status: ${status}"
            return 0
        fi
        log "DEBUG" "Attempt $retries of $MAX_RETRIES. Waiting $SLEEP_TIME seconds..."
        log "INFO" "Waiting for status ${status}... (attempt $((retries + 1))/${max_retries}) current_status is ${current_status}..."
        sleep $sleep_time
        retries=$((retries + 1))
    done
    
    log "ERROR" "Timeout waiting for cluster ${CLUSTER_NAME} to reach status: ${status}"
    return 1
}

function start_cluster_installation() {
    log "INFO" "Starting installation for cluster ${CLUSTER_NAME}..."

    # Check current status
    current_status=$(aicli info cluster "$CLUSTER_NAME" -f status -v)
    if [ "$current_status" == "installed" ]; then
        log "INFO" "Cluster ${CLUSTER_NAME} is already installed. Fetching kubeconfig..."
        get_kubeconfig
        return 0
    fi

    log "INFO" "Waiting for cluster to be ready..."
    wait_for_cluster_status "ready"
    aicli start cluster ${CLUSTER_NAME}
    log "INFO" "Waiting for installation to complete..."
    wait_for_cluster_status "installed"
    log "INFO" "Cluster installation completed successfully"
    get_kubeconfig
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

    echo "KUBECONFIG: $kubeconfig_path"
    if [ ! -f "$kubeconfig_path" ]; then
        log "INFO" "Downloading kubeconfig for $CLUSTER_NAME"
        aicli download kubeconfig "$CLUSTER_NAME"
        cp "kubeconfig.$CLUSTER_NAME" "$kubeconfig_path"
        log "INFO" "Kubeconfig downloaded to $KUBECONFIG"
    else
        log "INFO" "Using existing kubeconfig at: $KUBECONFIG"
    fi
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
    log "INFO" "Deleting VMs with prefix $VM_PREFIX..."
    env VM_PREFIX="$VM_PREFIX" scripts/delete_vms.sh || true
    
    # Clean resources
    clean_resources
    
    log "Full cleanup complete"
}

# -----------------------------------------------------------------------------
# ISO management functions
# -----------------------------------------------------------------------------

function create_day2_cluster() {
    # Create a day2 cluster for adding worker nodes to existing cluster
    local day2_cluster="${CLUSTER_NAME}-day2"

    # Check if main cluster exists
    if ! aicli info cluster "${CLUSTER_NAME}" >/dev/null 2>&1; then
        log "ERROR" "Main cluster ${CLUSTER_NAME} not found. Create it first."
        return 1
    fi

    # Check if day2 cluster already exists
    if ! aicli info cluster ${day2_cluster} >/dev/null 2>&1; then
        log "INFO" "Creating day2 cluster for adding nodes to ${CLUSTER_NAME}"

        # Get original cluster version for consistency
        local original_version=$(aicli info cluster ${CLUSTER_NAME} -f openshift_version -v 2>/dev/null)
        if [ -z "${original_version}" ]; then
            log "ERROR" "Could not determine OpenShift version of the original cluster"
            return 1
        fi

        # Create day2 cluster
        aicli create cluster \
            -P openshift_version="${original_version}" \
            -P base_dns_domain="${BASE_DOMAIN}" \
            -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
            -P public_key="${SSH_KEY}" \
            -P day2=true \
            "${day2_cluster}" >/dev/null 2>&1

        log "INFO" "Day2 cluster created successfully: ${day2_cluster}"
    else
        log "INFO" "Day2 cluster ${day2_cluster} already exists"
    fi

    return 0
}

function get_iso() {
    # Unified function to get ISO URL or download ISO
    # Parameters:
    #   $1 - cluster_name: Name of the cluster (defaults to CLUSTER_NAME env var)
    #   $2 - node_type: "master" or "worker" (default: master)
    #   $3 - action: "url" or "download" (default: download)
    #   $4 - download_path: Path to download ISO (optional)
    #   $5 - iso_type: "minimal" or "full" (default: minimal)
    
    local cluster_name="${1:-${CLUSTER_NAME}}"
    local node_type="${2:-master}"
    local action="${3:-download}"
    local download_path="${4:-${ISO_FOLDER}}"
    local iso_type="${5:-minimal}"  # Default to minimal explicitly
    local day2_cluster_name="${cluster_name}-day2"
    local iso_url=""
    
    # For worker nodes, we need to handle day2 cluster
    if [ "${node_type}" = "worker" ]; then
        # Ensure day2 cluster exists
        if ! aicli info cluster ${day2_cluster_name} >/dev/null 2>&1; then
            log "INFO" "Day2 cluster ${day2_cluster_name} not found, creating first..."
            create_day2_cluster
        fi
        
        # Get cluster ID
        local cluster_id=$(aicli list clusters | grep "${day2_cluster_name}" | awk '{print $2}' 2>/dev/null || echo "")
        if [ -z "${cluster_id}" ]; then
            log "ERROR" "Could not find day2 cluster ${day2_cluster_name}"
            return 1
        fi
        
        # Get ISO URL via InfraEnv (best approach for token-based URLs)
        log "INFO" "Getting ISO URL for worker nodes..."
        
        # Get the infraenv ID
        local infraenv_output=$(aicli list infraenvs 2>/dev/null)
        local infraenv_id=$(echo "$infraenv_output" | grep "${day2_cluster_name}" | awk -F'|' '{print $2}' | tr -d ' ' 2>/dev/null)
        
        # If InfraEnv found, get ISO URL
        if [ -n "${infraenv_id}" ]; then
            local infraenv_info=$(aicli info infraenv ${infraenv_id} 2>/dev/null)
            iso_url=$(echo "$infraenv_info" | grep "download_url:" | sed 's/download_url: //' 2>/dev/null || echo "")
            
            # Handle token URLs and ISO type
            if [ -n "${iso_url}" ]; then
                if [[ "${iso_url}" =~ /bytoken/ ]]; then
                    # Token-based URL - preserve format but adjust ISO type if needed
                    if [ "${iso_type}" = "minimal" ] && [[ "${iso_url}" =~ full\.iso$ ]]; then
                        iso_url="${iso_url/full.iso/minimal.iso}"
                    elif [ "${iso_type}" = "full" ] && [[ "${iso_url}" =~ minimal\.iso$ ]]; then
                        iso_url="${iso_url/minimal.iso/full.iso}"
                    fi
                else
                    # Non-token URL - adjust ISO type if needed
                    if [ "${iso_type}" = "minimal" ] && [[ "${iso_url}" =~ full\.iso$ ]]; then
                        iso_url="${iso_url/full.iso/minimal.iso}"
                    elif [ "${iso_type}" = "full" ] && [[ "${iso_url}" =~ minimal\.iso$ ]]; then
                        iso_url="${iso_url/minimal.iso/full.iso}"
                    fi
                fi
            fi
        fi
        
        # Fallback to UI URL if needed
        if [ -z "${iso_url}" ]; then
            log "INFO" "No direct URL found. Login to console.redhat.com/openshift, select your cluster, and click 'Add hosts' to generate an ISO."
            iso_url="https://console.redhat.com/openshift"
        fi
        
        # Worker nodes don't support download action
        if [ "${action}" = "download" ]; then
            log "ERROR" "Worker ISO download not supported, use URL to download manually"
            echo "${iso_url}"
            return 1
        fi
    else
        # For master nodes
        if [ "${action}" = "url" ]; then
            # Get URL for master node
            iso_url=$(aicli info cluster "${cluster_name}" | grep -i "^iso_download_url:" | awk '{print $2}')
        elif [ "${action}" = "download" ]; then
            # Download for master node using aicli
            log "INFO" "Downloading master ISO to ${download_path}"
            
            if [ ! -d "${download_path}" ]; then
                mkdir -p "${download_path}"
            fi
            
            if ! aicli download iso "${cluster_name}" -p "${download_path}"; then
                log "ERROR" "Failed to download ISO for cluster ${cluster_name}"
                return 1
            fi
            
            log "INFO" "ISO downloaded to ${download_path}"
            return 0
        fi
    fi
    
    # For URL action, print the URL and return
    if [ "${action}" = "url" ]; then
        if [ -n "${iso_url}" ]; then
            echo "${iso_url}"
            export ISO_URL="${iso_url}"
            return 0
        else
            log "ERROR" "Could not get ISO URL for ${node_type} nodes"
            return 1
        fi
    fi
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
        download-iso)
            # Download ISO for master nodes
            get_iso "${CLUSTER_NAME}" "master" "download" "${ISO_FOLDER}" "minimal"
            ;;
        get-worker-iso)
            # Get worker ISO URL
            get_iso "${CLUSTER_NAME}" "worker" "url" "" "minimal"
            ;;
        get-iso)
            # Get ISO with custom parameters
            get_iso "$@"
            ;;
        create-day2-cluster)
            create_day2_cluster
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: check-create-cluster, delete-cluster, cluster-install,"
            log "  wait-for-status, get-kubeconfig, clean-all, download-iso, create-day2-cluster, get-worker-iso, get-iso"
            exit 1
            ;;
    esac
}

# If script is executed directly (not sourced), run the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log "INFO" "Usage: $0 <command> [arguments...]"
        exit 1
    fi
    
    main "$@"
fi 