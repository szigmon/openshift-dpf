#!/bin/bash
# nfs-service.sh - NFS server setup and configuration
# This script sets up an NFS server with systemd service and firewall configuration

# Exit on error and catch pipe failures
set -e
set -o pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# -----------------------------------------------------------------------------
# NFS Configuration Variables
# -----------------------------------------------------------------------------
NFS_EXPORT_DIR=${NFS_EXPORT_DIR:-"/nfs/exports"}
NFS_EXPORT_OPTIONS=${NFS_EXPORT_OPTIONS:-"rw,sync,no_root_squash,no_subtree_check"}
NFS_ALLOWED_NETWORK=${NFS_ALLOWED_NETWORK:-"*"}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

function detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_ID="${VERSION_ID}"
        log "INFO" "Detected OS: ${OS_ID} ${OS_VERSION_ID}"
    else
        log "ERROR" "Cannot detect OS type. /etc/os-release not found"
        return 1
    fi
}

function install_nfs_packages() {
    log "INFO" "Installing NFS server packages..."
    
    case "${OS_ID}" in
        rhel|centos|fedora)
            if command -v dnf &> /dev/null; then
                sudo dnf install -y nfs-utils
            else
                sudo yum install -y nfs-utils
            fi
            ;;
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y nfs-kernel-server
            ;;
        *)
            log "ERROR" "Unsupported OS: ${OS_ID}"
            return 1
            ;;
    esac
    
    log "INFO" "NFS packages installed successfully"
}

function create_export_directory() {
    log "INFO" "Creating NFS export directory: ${NFS_EXPORT_DIR}"
    
    if [ -d "${NFS_EXPORT_DIR}" ]; then
        log "INFO" "Export directory already exists: ${NFS_EXPORT_DIR}"
    else
        sudo mkdir -p "${NFS_EXPORT_DIR}"
        log "INFO" "Created export directory: ${NFS_EXPORT_DIR}"
    fi
    
    # Set proper permissions
    sudo chmod -R 755 "${NFS_EXPORT_DIR}"
    sudo chown -R nobody:nogroup "${NFS_EXPORT_DIR}" 2>/dev/null || \
        sudo chown -R nfsnobody:nfsnobody "${NFS_EXPORT_DIR}" 2>/dev/null || \
        log "WARN" "Could not set ownership to nobody/nfsnobody, using current ownership"
    
    log "INFO" "Set permissions on export directory"
}

function configure_nfs_exports() {
    log "INFO" "Configuring NFS exports..."
    
    local export_line="${NFS_EXPORT_DIR} ${NFS_ALLOWED_NETWORK}(${NFS_EXPORT_OPTIONS})"
    local exports_file="/etc/exports"
    
    # Backup existing exports file
    if [ -f "${exports_file}" ]; then
        sudo cp "${exports_file}" "${exports_file}.backup.$(date +%Y%m%d_%H%M%S)"
        log "INFO" "Backed up existing exports file"
    fi
    
    # Check if export already exists
    if sudo grep -qF "${NFS_EXPORT_DIR}" "${exports_file}" 2>/dev/null; then
        log "INFO" "Export for ${NFS_EXPORT_DIR} already exists in ${exports_file}"
    else
        echo "${export_line}" | sudo tee -a "${exports_file}" > /dev/null
        log "INFO" "Added export to ${exports_file}: ${export_line}"
    fi
    
    # Export the shared directories
    sudo exportfs -ra
    log "INFO" "NFS exports refreshed"
}

function configure_firewall() {
    log "INFO" "Configuring firewall for NFS..."
    
    # Check if firewalld is available and running
    if ! command -v firewall-cmd &> /dev/null; then
        log "ERROR" "firewall-cmd not found. This script requires firewalld."
        log "ERROR" "Install firewalld: sudo dnf install firewalld"
        return 1
    fi
    
    # Check if firewalld is running
    if ! sudo firewall-cmd --state &> /dev/null; then
        log "WARN" "firewalld is not running. Starting firewalld..."
        sudo systemctl start firewalld
        sudo systemctl enable firewalld
        
        if ! sudo firewall-cmd --state &> /dev/null; then
            log "ERROR" "Failed to start firewalld"
            return 1
        fi
    fi
    
    log "INFO" "Configuring firewalld for NFS services..."
    
    # Add NFS service (includes ports 2049, 111, 20048)
    sudo firewall-cmd --permanent --add-service=nfs
    sudo firewall-cmd --permanent --add-service=rpc-bind
    sudo firewall-cmd --permanent --add-service=mountd
    
    # Reload firewall to apply changes
    sudo firewall-cmd --reload
    
    # Verify rules were applied
    if sudo firewall-cmd --list-services | grep -q "nfs"; then
        log "INFO" "✅ Firewalld rules applied successfully"
    else
        log "ERROR" "Failed to apply firewalld rules"
        return 1
    fi
}

function enable_nfs_services() {
    log "INFO" "Enabling and starting NFS services..."
    
    case "${OS_ID}" in
        rhel|centos|fedora)
            # Enable and start required services
            sudo systemctl enable rpcbind nfs-server
            sudo systemctl start rpcbind
            sudo systemctl start nfs-server
            
            # Verify services are running
            if sudo systemctl is-active --quiet nfs-server; then
                log "INFO" "NFS server is running"
            else
                log "ERROR" "NFS server failed to start"
                return 1
            fi
            ;;
        ubuntu|debian)
            sudo systemctl enable nfs-kernel-server
            sudo systemctl start nfs-kernel-server
            
            if sudo systemctl is-active --quiet nfs-kernel-server; then
                log "INFO" "NFS kernel server is running"
            else
                log "ERROR" "NFS kernel server failed to start"
                return 1
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS: ${OS_ID}"
            return 1
            ;;
    esac
    
    log "INFO" "NFS services enabled and started successfully"
}

function verify_nfs_setup() {
    log "INFO" "Verifying NFS setup..."
    
    # Check if exports are active
    if sudo exportfs -v | grep -q "${NFS_EXPORT_DIR}"; then
        log "INFO" "✅ NFS export is active: ${NFS_EXPORT_DIR}"
    else
        log "ERROR" "❌ NFS export not found in active exports"
        return 1
    fi
    
    # Check if NFS ports are listening
    local nfs_listening=false
    if ss -tunlp 2>/dev/null | grep -q ":2049" || netstat -tunlp 2>/dev/null | grep -q ":2049"; then
        log "INFO" "✅ NFS port 2049 is listening"
        nfs_listening=true
    else
        log "WARN" "❌ NFS port 2049 is not listening"
    fi
    
    if [ "$nfs_listening" = false ]; then
        log "ERROR" "NFS setup verification failed"
        return 1
    fi
    
    log "INFO" "✅ NFS setup verification completed successfully"
}

function display_nfs_info() {
    echo ""
    echo "================================================================================"
    echo "✅ NFS Server Setup Complete!"
    echo "================================================================================"
    echo ""
    echo "NFS Server Configuration:"
    echo "  Export Directory: ${NFS_EXPORT_DIR}"
    echo "  Export Options:   ${NFS_EXPORT_OPTIONS}"
    echo "  Allowed Network:  ${NFS_ALLOWED_NETWORK}"
    echo ""
    echo "To use this NFS server in your .env file, add:"
    echo "  export NFS_SERVER_NODE_IP=\"$(hostname -I | awk '{print $1}')\""
    echo "  export NFS_PATH=\"${NFS_EXPORT_DIR}\""
    echo ""
    echo "Active NFS Exports:"
    sudo exportfs -v | grep "${NFS_EXPORT_DIR}" || echo "  (none found)"
    echo ""
    echo "================================================================================"
}

# -----------------------------------------------------------------------------
# Main Function
# -----------------------------------------------------------------------------
function main() {
    log "INFO" "Starting NFS server setup..."
    
    # Check if running as root or with sudo
    if [ "$EUID" -eq 0 ]; then
        log "WARN" "Running as root. It's recommended to run with sudo instead."
    fi
    
    # Detect OS
    detect_os
    
    # Install NFS packages
    install_nfs_packages
    
    # Create export directory
    create_export_directory
    
    # Configure NFS exports
    configure_nfs_exports
    
    # Configure firewall
    configure_firewall
    
    # Enable and start NFS services
    enable_nfs_services
    
    # Verify setup
    verify_nfs_setup
    
    # Display information
    display_nfs_info
    
    log "INFO" "NFS server setup completed successfully!"
}

# -----------------------------------------------------------------------------
# Script Entry Point
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

