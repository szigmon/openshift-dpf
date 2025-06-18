#!/bin/bash
# utils.sh - Common utilities for DPF cluster management

# Exit on error
set -e

# Source environment variables
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# -----------------------------------------------------------------------------
# Logging utility
# -----------------------------------------------------------------------------
log() {
    local level=${1:-INFO}
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Debugging output

    # Skip empty messages
    if [ -z "$message" ]; then
        echo "DEBUG: log function received an empty message, skipping..." >&2
        return
    fi

    case "$level" in
        "INFO")
            echo -e "\033[0;32m[${timestamp}] [INFO] ${message}\033[0m"
            ;;
        "WARN")
            echo -e "\033[0;33m[${timestamp}] [WARN] ${message}\033[0m"
            ;;
        "ERROR")
            echo -e "\033[0;31m[${timestamp}] [ERROR] ${message}\033[0m" >&2
            ;;
        "DEBUG")
            if [ "${DEBUG:-false}" = "true" ]; then
                echo -e "\033[0;36m[${timestamp}] [DEBUG] ${message}\033[0m"
            fi
            ;;
        *)
            echo -e "[${timestamp}] [${level}] ${message}"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# File verification functions
# -----------------------------------------------------------------------------
function verify_files() {
    log "INFO" "Verifying required files..."
    
    if [ ! -f "${OPENSHIFT_PULL_SECRET}" ]; then
        log "ERROR" "${OPENSHIFT_PULL_SECRET} not found"
        exit 1
    fi

    if [ ! -f "${DPF_PULL_SECRET}" ]; then
        log "ERROR" "${DPF_PULL_SECRET} not found"
        exit 1
    fi

    if [ ! -f "${MANIFESTS_DIR}/cluster-installation/ovn-values.yaml" ]; then
        log "ERROR" "${MANIFESTS_DIR}/cluster-installation/ovn-values.yaml not found"
        exit 1
    fi

    log "INFO" "All required files verified successfully"
}

# -----------------------------------------------------------------------------
# Resource waiting functions
# -----------------------------------------------------------------------------
function wait_for_resource() {
    local namespace=$1
    local resource_type=$2
    local resource_name=$3
    local max_attempts=${4:-30}
    local delay=${5:-5}

    log "INFO" "Waiting for $resource_type/$resource_name in namespace $namespace..."

    for i in $(seq 1 "$max_attempts"); do
        if oc get "$resource_type" -n "$namespace" "$resource_name" &>/dev/null; then
            log "INFO" "$resource_type/$resource_name found in namespace $namespace"
            return 0
        fi
        log "INFO" "Waiting for $resource_type/$resource_name (attempt $i/$max_attempts)..."
        sleep "$delay"
    done

    log "ERROR" "Timed out waiting for $resource_type/$resource_name in namespace $namespace"
    return 1
}

function wait_for_secret_with_data() {
    local namespace=$1
    local secret_name=$2
    local key=$3
    local max_attempts=${4:-30}
    local delay=${5:-5}

    log "INFO" "Waiting for secret/$secret_name with valid data for key $key in namespace $namespace..."

    # Use retry to check for secret data existence
    retry "$max_attempts" "$delay" bash -c '
        ns="$1"; secret="$2"; key="$3"
        data=$(oc get secret -n "$ns" "$secret" -o jsonpath="{.data.${key}}" 2>/dev/null)
        [ -n "$data" ]
    ' _ "$namespace" "$secret_name" "$key"
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
            log "INFO" "$label pods are ready"
            return 0
        fi
        log "INFO" "Waiting for $label pods (attempt $i/$max_attempts)..."
        sleep "$delay"
    done

    log "ERROR" "$label pods failed to become ready"
    oc get pods -n "$namespace"
    oc describe pod -n "$namespace" -l "$label"
    exit 1
}

# -----------------------------------------------------------------------------
# Resource checking functions
# -----------------------------------------------------------------------------
function check_namespace_exists() {
    local namespace=$1
    if oc get namespace "$namespace" &>/dev/null; then
        log [INFO] "Namespace $namespace already exists"
        return 0
    fi
    return 1
}

function check_crd_exists() {
    local crd=$1
    if oc get crd "$crd" &>/dev/null; then
        log [INFO] "CRD $crd already exists"
        return 0
    fi
    return 1
}

function check_secret_exists() {
    local namespace=$1
    local secret=$2
    if oc get secret -n "$namespace" "$secret" &>/dev/null; then
        log [INFO] "Secret $secret already exists in namespace $namespace"
        return 0
    fi
    return 1
}

function check_resource_exists() {
    local file=$1
    local resource_type=$(grep -m 1 "kind:" "$file" | awk '{print $2}')
    local resource_name=$(grep -m 1 "name:" "$file" | awk '{print $2}')
    local namespace=$(grep -m 1 "namespace:" "$file" | awk '{print $2}')
    
    if [ -n "$namespace" ]; then
        if oc get "$resource_type" -n "$namespace" "$resource_name" &>/dev/null; then
            log "INFO" "$resource_type/$resource_name already exists in namespace $namespace."
            return 0
        fi
    else
        if oc get "$resource_type" "$resource_name" &>/dev/null; then
            log "INFO" "$resource_type/$resource_name already exists."
            return 0
        fi
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Manifest application functions
# -----------------------------------------------------------------------------
function apply_manifest() {
    local file=$1
    local apply_always=${2:-false}

    # Skip existence check if apply_always is true
    if [ "$apply_always" != "true" ]; then
        if check_resource_exists "$file"; then
            log "INFO" "Skipping application of $file as it already exists."
            return 0
        fi
    else
        log "INFO" "Applying $file (apply_always=true)..."
    fi
    
    log "INFO" "Applying $file..."
    oc apply -f "$file"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Failed to apply $file (exit code: $exit_code)"
        return $exit_code
    fi
    return 0
}

function retry() {
    local retries=$1
    local delay=$2
    shift 2
    local attempt=0

    while (( attempt < retries )); do
        "$@" && return 0
        attempt=$(( attempt + 1 ))
        echo "Attempt $attempt failed. Retrying in $delay seconds..."
        sleep "$delay"
    done

    echo "All $retries attempts failed."
    return 1
}

# -----------------------------------------------------------------------------
# Template processing functions
# -----------------------------------------------------------------------------
function process_template() {
    local template_file=$1
    local output_file=$2
    shift 2
    
    log "INFO" "Processing template: $(basename "$template_file")"
    
    # Validate input file exists
    if [ ! -f "$template_file" ]; then
        log "ERROR" "Template file not found: $template_file"
        return 1
    fi
    
    # Copy template to output
    cp "$template_file" "$output_file" || {
        log "ERROR" "Failed to copy $template_file to $output_file"
        return 1
    }
    
    # Apply each substitution
    while [ $# -gt 0 ]; do
        local placeholder=$1
        local value=$2
        sed -i "s|${placeholder}|${value}|g" "$output_file"
        log "DEBUG" "Replaced ${placeholder} with ${value} in $(basename "$output_file")"
        shift 2
    done
    
    log "INFO" "Template processed successfully: $(basename "$output_file")"
}

# -----------------------------------------------------------------------------
# Cleanup functions
# -----------------------------------------------------------------------------
function clean_resources() {
    log "INFO" "Cleaning up resources..."
    
    # Clean up generated files
    rm -rf "$GENERATED_DIR" || true
    rm -f "kubeconfig.$CLUSTER_NAME" || true
    rm -f "$HOSTED_CLUSTER_NAME.kubeconfig" || true
    rm -f "$KUBECONFIG" || true
    
    log "INFO" "Cleanup complete"
}

# If script is executed directly (not sourced), handle commands
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    command=$1
    case $command in
        verify-files)
            verify_files
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            echo "Available commands: verify-files"
            exit 1
            ;;
    esac
fi 