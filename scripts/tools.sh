#!/bin/bash
# tools.sh - Tool installation and management

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# -----------------------------------------------------------------------------
# Tool installation functions
# -----------------------------------------------------------------------------
function ensure_helm_installed() {
    if ! command -v helm &> /dev/null; then
        log "INFO" "Helm not found. Installing helm..."
        install_helm
    else
        log "INFO" "Helm is already installed. Version: $(helm version --short)"
    fi
}

function install_helm() {
    log "INFO" "Installing Helm $(if [ -n "$HELM_VERSION" ]; then echo $HELM_VERSION; else echo "latest"; fi)..."
    
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    DESIRED_VERSION=$HELM_VERSION ./get_helm.sh
    rm get_helm.sh

    log "INFO" "Helm installation complete. Installed version: $(helm version --short)"
}

function install_hypershift() {
    log "WARN" "Direct HyperShift installation is deprecated in favor of MCE (MultiCluster Engine)"
    log "INFO" "HyperShift is now managed through MCE operator"
    log "INFO" ""
    log "INFO" "To install HyperShift:"
    log "INFO" "1. Run 'make deploy-dpf' which will automatically install MCE"
    log "INFO" "2. MCE will manage HyperShift installation and lifecycle"
    log "INFO" ""
    log "INFO" "For existing clusters with HyperShift already installed:"
    log "INFO" "1. Run 'make test-mce-ready' to check readiness for migration"
    log "INFO" "2. Run 'make migrate-to-mce' to migrate to MCE-managed HyperShift"
    log "INFO" ""
    log "INFO" "If you still need to install the hypershift CLI binary:"
    
    # Create a temporary container and copy the hypershift binary
    CONTAINER_COMMAND=${CONTAINER_COMMAND:-podman}
    $CONTAINER_COMMAND cp $($CONTAINER_COMMAND create --name hypershift --rm --pull always $HYPERSHIFT_IMAGE):/usr/bin/hypershift /tmp/hypershift
    $CONTAINER_COMMAND rm -f hypershift

    # Install the hypershift binary
    sudo install -m 0755 -o root -g root /tmp/hypershift /usr/local/bin/hypershift
    rm -f /tmp/hypershift
    
    log "INFO" "HyperShift CLI binary installed to /usr/local/bin/hypershift"
    log "WARN" "Note: The operator should be installed via MCE, not directly"
}

function install_oc() {
    # Download the OpenShift CLI
    log "INFO" "Downloading OpenShift CLI..."
    wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz

    # Extract the archive
    tar -xzf openshift-client-linux.tar.gz

    # Move the oc binary to a directory in your PATH
    sudo mv oc /usr/local/bin/

    # Verify the installation
    oc version
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    case "$command" in
        install-helm)
            install_helm
            ;;
        install-hypershift)
            install_hypershift
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: install-helm, install-hypershift"
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
