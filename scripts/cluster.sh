#!/bin/bash
# cluster.sh - Cluster management operations

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

function download_iso() {
    log "INFO" "Downloading ISO for cluster ${CLUSTER_NAME} to ${ISO_FOLDER}"
    
    if [ -z "${ISO_FOLDER}" ]; then
        log "ERROR" "ISO_FOLDER is not set. Please provide a valid ISO_FOLDER path."
        exit 1
    fi

    if [ ! -d "${ISO_FOLDER}" ]; then
        log "INFO" "Creating ISO folder: ${ISO_FOLDER}"
        mkdir -p "${ISO_FOLDER}"
    fi

    if ! aicli download iso "${CLUSTER_NAME}" -p "${ISO_FOLDER}"; then
        log "ERROR" "Failed to download ISO for cluster ${CLUSTER_NAME}"
        exit 1
    fi
    
    log "INFO" "ISO downloaded successfully to ${ISO_FOLDER}"
}

function modify_iso_url() {
    # Helper function to modify ISO URL based on iso_type
    # Parameters:
    #   $1 - Original ISO URL
    #   $2 - Requested ISO type (minimal or full)
    
    local iso_url="$1"
    local iso_type="$2"
    
    # If URL is empty or not http/https, return as is
    if [ -z "${iso_url}" ] || [[ ! "${iso_url}" =~ ^https?:// ]]; then
        echo "${iso_url}"
        return
    fi
    
    log "INFO" "Original ISO URL: ${iso_url}"
    
    # If URL has full.iso but we want minimal, change it
    if [ "${iso_type}" = "minimal" ] && [[ "${iso_url}" == *"full.iso"* ]]; then
        iso_url="${iso_url/full.iso/minimal.iso}"
        log "INFO" "Using minimal ISO (URL modified)"
    # If URL has minimal.iso but we want full, change it
    elif [ "${iso_type}" = "full" ] && [[ "${iso_url}" == *"minimal.iso"* ]]; then
        iso_url="${iso_url/minimal.iso/full.iso}"
        log "INFO" "Using full ISO (URL modified)"
    # Otherwise, report what we're using but also check if we need to enforce our preference
    elif [[ "${iso_url}" == *"minimal.iso"* ]]; then
        if [ "${iso_type}" = "full" ]; then
            iso_url="${iso_url/minimal.iso/full.iso}"
            log "INFO" "Enforcing full ISO (URL modified)"
        else
            log "INFO" "Using minimal ISO (URL unchanged)"
        fi
    elif [[ "${iso_url}" == *"full.iso"* ]]; then
        if [ "${iso_type}" = "minimal" ]; then
            iso_url="${iso_url/full.iso/minimal.iso}"
            log "INFO" "Enforcing minimal ISO (URL modified)"
        else
            log "INFO" "Using full ISO (URL unchanged)"
        fi
    fi
    
    echo "${iso_url}"
}

function get_iso() {
    # Unified function to get ISO URL or download ISO
    # Parameters:
    #   $1 - cluster_name: Name of the cluster (defaults to CLUSTER_NAME from env)
    #   $2 - node_type: "master" or "worker" (default: master)
    #   $3 - action: "url" or "download" (default: download)
    #   $4 - download_path: Path to download ISO (optional)
    #   $5 - iso_type: "minimal" or "full" (default: minimal)
    
    local cluster_name="${1:-${CLUSTER_NAME}}"
    local node_type="${2:-master}"
    local action="${3:-download}"
    local download_path="${4:-${ISO_FOLDER}}"
    local iso_type="${5:-${ISO_TYPE:-minimal}}"  # Get from param or ENV, default to minimal
    local day2_cluster_name="${cluster_name}-day2"
    
    # Normalize ISO type by removing any -iso suffix
    iso_type="${iso_type%-iso}"
    
    # Basic validation
    if [ -z "${cluster_name}" ]; then
        log "ERROR" "Cluster name is required"
        exit 1
    fi
    
    # For worker nodes, we need a day2 cluster
    if [ "${node_type}" = "worker" ]; then
        # Make sure the day2 cluster exists
        if ! aicli info cluster ${day2_cluster_name} >/dev/null 2>&1; then
            log "INFO" "Creating day2 cluster for worker nodes"
            
            # Get original cluster version for consistency
            local original_version=$(aicli info cluster ${cluster_name} -f openshift_version -v 2>/dev/null)
            if [ -z "${original_version}" ]; then
                log "ERROR" "Could not determine OpenShift version of the original cluster"
                exit 1
            fi
            
            # Create day2 cluster - don't specify ISO type to use default
            aicli create cluster \
                -P openshift_version="${original_version}" \
                -P base_dns_domain="${BASE_DOMAIN}" \
                -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
                -P public_key="${SSH_KEY}" \
                -P day2=true \
                "${day2_cluster_name}" >/dev/null
                
            log "INFO" "Day2 cluster ${day2_cluster_name} created successfully"
        fi
        
        # Handle worker node ISO
        if [ "${action}" = "url" ]; then
            # Get ISO URL for workers
            log "INFO" "Getting ISO URL for worker nodes (ISO type: ${iso_type})"
            
            # Get ISO URL using infraenv method (more reliable)
            local infraenv_id=$(aicli list infraenvs 2>/dev/null | grep "${day2_cluster_name}" | awk -F'|' '{print $2}' | tr -d ' \t' | head -1)
            local iso_url=""
            
            if [ -n "${infraenv_id}" ]; then
                iso_url=$(aicli info infraenv "${infraenv_id}" 2>/dev/null | grep -E "(download_url|iso_download_url):" | awk '{print $2}')
            fi
            
            # Fallback to direct method if infraenv failed
            if [ -z "${iso_url}" ]; then
                iso_url=$(aicli info iso "${day2_cluster_name}" 2>/dev/null | grep -i "url:" | awk '{print $2}')
            fi
            
            # Apply ISO type - modify URL based on iso_type
            iso_url=$(modify_iso_url "${iso_url}" "${iso_type}")
            
            if [ -n "${iso_url}" ] && [[ "${iso_url}" =~ ^https?:// ]]; then
                echo -e "\033[1;32mISO URL for worker nodes: \033[1;36m${iso_url}\033[0m"
                export ISO_URL="${iso_url}"
                return 0
            else
                # Last resort fallback to UI URL
                local cluster_id=$(aicli info cluster "${day2_cluster_name}" 2>/dev/null | grep -i "id:" | awk '{print $2}' | tr -d ' \t')
                if [ -n "${cluster_id}" ]; then
                    iso_url="https://console.redhat.com/openshift/assisted-installer/clusters/${cluster_id}/add-hosts"
                    echo -e "\033[1;32mISO URL for worker nodes (UI): \033[1;36m${iso_url}\033[0m"
                    export ISO_URL="${iso_url}"
                    return 0
                else
                    log "ERROR" "Could not get ISO URL for worker nodes"
                    exit 1
                fi
            fi
        else
            # Download ISO
            log "INFO" "Downloading worker ISO to ${download_path}"
            if [ ! -d "${download_path}" ]; then
                mkdir -p "${download_path}"
            fi
            aicli download iso "${day2_cluster_name}" -p "${download_path}"
            log "INFO" "Worker ISO downloaded to ${download_path}"
        fi
    else
        # For master nodes, use the main cluster
        if [ "${action}" = "url" ]; then
            # Get ISO URL for masters
            log "INFO" "Getting ISO URL for master nodes (ISO type: ${iso_type})"
            local iso_url=$(aicli info iso "${cluster_name}" 2>/dev/null | grep -i "url:" | awk '{print $2}')
            
            # Apply ISO type
            iso_url=$(modify_iso_url "${iso_url}" "${iso_type}")
            
            if [ -n "${iso_url}" ] && [[ "${iso_url}" =~ ^https?:// ]]; then
                echo -e "\033[1;32mISO URL for master nodes: \033[1;36m${iso_url}\033[0m"
                export ISO_URL="${iso_url}"
                return 0
            else
                log "ERROR" "Could not get ISO URL for master nodes"
                exit 1
            fi
        else
            # Download master ISO
            if [ -n "${download_path}" ]; then
                ISO_FOLDER="${download_path}"
            fi
            download_iso
        fi
    fi
}

function create_day2_cluster() {
    # Create a day2 cluster for worker nodes and get the ISO URL
    log "INFO" "Creating day2 cluster for worker nodes and getting ISO URL"
    
    # Check if original cluster exists
    if ! aicli info cluster ${CLUSTER_NAME} >/dev/null 2>&1; then
        log "ERROR" "Main cluster ${CLUSTER_NAME} doesn't exist. Please create it first."
        exit 1
    fi
    
    # Get ISO type - prioritize command-line argument, then environment variable
    local iso_type="minimal"  # Default to minimal
    
    # Check if ISO_TYPE was passed as a parameter
    if [ "$1" = "ISO_TYPE" ] && [ -n "$2" ]; then
        iso_type="$2"
    # Otherwise use environment variable if set
    elif [ -n "${ISO_TYPE}" ]; then
        iso_type="${ISO_TYPE}"
    fi
    
    # Normalize ISO type by removing any -iso suffix
    iso_type="${iso_type%-iso}"
    
    log "INFO" "Using ISO type: ${iso_type}"
    
    # Use the get_iso function with worker type and url action
    get_iso "${CLUSTER_NAME}" "worker" "url" "" "${iso_type}"
}

function download_worker_iso() {
    # Get worker ISO URL using the get_iso function
    log "INFO" "Getting ISO URL for worker nodes"
    
    # Get ISO type from environment or use default
    local iso_type="${ISO_TYPE:-minimal}"
    # Normalize ISO type by removing any -iso suffix
    iso_type="${iso_type%-iso}"
    
    log "INFO" "Using ISO type: ${iso_type}"
    
    get_iso "${CLUSTER_NAME}" "worker" "url" "" "${iso_type}"
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
            download_iso
            ;;
        create-day2-cluster)
            create_day2_cluster "$@"
            ;;
        get-worker-iso)
            download_worker_iso
            ;;
        get-iso)
            get_iso "$@"
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