#!/bin/bash
# post-install.sh - Prepare and apply post-installation manifests to the cluster

# Exit on error
set -e

# Source common utilities and configuration
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"

# Configuration
MANIFESTS_DIR=${MANIFESTS_DIR:-"manifests"}
POST_INSTALL_DIR="${MANIFESTS_DIR}/post-installation"
GENERATED_DIR=${GENERATED_DIR:-"$MANIFESTS_DIR/generated"}
GENERATED_POST_INSTALL_DIR="${GENERATED_DIR}/post-install"

# BFB Configuration with defaults
BFB_URL=${BFB_URL:-"http://10.8.2.236/bfb/rhcos_4.19.0-ec.4_installer_2025-04-23_07-48-42.bfb"}

# HBN OVN Configuration with defaults
HBN_OVN_NETWORK=${HBN_OVN_NETWORK:-"10.0.120.0/22"}

function update_bfb_manifest() {
    log [INFO] "Updating BFB manifest with custom URL and filename..."
    
    # Create generated directory if it doesn't exist
    mkdir -p "${GENERATED_POST_INSTALL_DIR}"
    
    # Extract filename from URL
    local bfb_filename=$(basename "${BFB_URL}")
    
    # Copy and update the BFB manifest
    cp "${POST_INSTALL_DIR}/bfb.yaml" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    
    # Update the manifest with custom values
    sed -i "s|fileName: BFB_FILENAME|fileName: ${bfb_filename}|g" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    sed -i "s|url: \"BFB_URL\"|url: \"${BFB_URL}\"|g" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    
    log [INFO] "BFB manifest updated successfully"
}

function update_hbn_ovn_manifests() {
    log [INFO] "Updating HBN OVN manifests with custom network..."
    
    # Create generated directory if it doesn't exist
    mkdir -p "${GENERATED_POST_INSTALL_DIR}"
    
    # Update hbn-ovn-ipam.yaml
    cp "${POST_INSTALL_DIR}/hbn-ovn-ipam.yaml" "${GENERATED_POST_INSTALL_DIR}/hbn-ovn-ipam.yaml"
    sed -i "s|network: \"HBN_OVN_NETWORK\"|network: \"${HBN_OVN_NETWORK}\"|g" "${GENERATED_POST_INSTALL_DIR}/hbn-ovn-ipam.yaml"
    
    # Update ovn-dpuservice.yaml
    cp "${POST_INSTALL_DIR}/ovn-dpuservice.yaml" "${GENERATED_POST_INSTALL_DIR}/ovn-dpuservice.yaml"
    sed -i "s|vtepCIDR: HBN_OVN_NETWORK|vtepCIDR: ${HBN_OVN_NETWORK}|g" "${GENERATED_POST_INSTALL_DIR}/ovn-dpuservice.yaml"
    
    log [INFO] "HBN OVN manifests updated successfully"
}

function prepare_post_installation() {
    log [INFO] "Starting post-installation manifest preparation..."
    
    # Check if post-installation directory exists
    if [ ! -d "${POST_INSTALL_DIR}" ]; then
        log [ERROR] "Post-installation directory not found: ${POST_INSTALL_DIR}"
        exit 1
    fi
    
    # Create generated post-install directory
    mkdir -p "${GENERATED_POST_INSTALL_DIR}"
    
    # Update manifests with custom values
    update_bfb_manifest
    update_hbn_ovn_manifests
    
    # Copy remaining manifests
    for file in "${POST_INSTALL_DIR}"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            # Skip files we've already processed
            if [[ "${filename}" != "bfb.yaml" && "${filename}" != "hbn-ovn-ipam.yaml" && "${filename}" != "ovn-dpuservice.yaml" ]]; then
                log [INFO] "Copying manifest: ${filename}"
                cp "$file" "${GENERATED_POST_INSTALL_DIR}/${filename}"
            fi
        fi
    done
    
    log [INFO] "Post-installation manifest preparation completed successfully"
}

function apply_post_installation() {
    log [INFO] "Starting post-installation manifest application..."
    
    # Check if generated post-installation directory exists
    if [ ! -d "${GENERATED_POST_INSTALL_DIR}" ]; then
        log [ERROR] "Generated post-installation directory not found: ${GENERATED_POST_INSTALL_DIR}"
        log [ERROR] "Please run prepare-dpu-files first"
        exit 1
    fi
    
    # Get kubeconfig
    get_kubeconfig
    
    # Apply each YAML file in the generated post-installation directory
    for file in "${GENERATED_POST_INSTALL_DIR}"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            log [INFO] "Applying post-installation manifest: ${filename}"
            apply_manifest "$file"
        fi
    done
    
    log [INFO] "Post-installation manifest application completed successfully"
}

# If script is executed directly (not sourced), run the appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log [ERROR] "Usage: $0 <prepare|apply>"
        exit 1
    fi
    
    case "$1" in
        prepare)
            prepare_post_installation
            ;;
        apply)
            apply_post_installation
            ;;
        *)
            log [ERROR] "Unknown command: $1"
            log [ERROR] "Available commands: prepare, apply"
            exit 1
            ;;
    esac
fi 