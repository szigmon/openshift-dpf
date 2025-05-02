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
        log "Helm not found. Installing helm..."
        install_helm
    else
        log "Helm is already installed. Version: $(helm version --short)"
    fi
}

function install_helm() {
    log "Installing Helm $(if [ -n "$HELM_VERSION" ]; then echo $HELM_VERSION; else echo "latest"; fi)..."
    
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    DESIRED_VERSION=$HELM_VERSION ./get_helm.sh
    rm get_helm.sh

    log "Helm installation complete. Installed version: $(helm version --short)"
}

function install_hypershift() {
    log "Installing Hypershift binary and operator..."

    # Create a temporary container and copy the hypershift binary
    CONTAINER_COMMAND=${CONTAINER_COMMAND:-podman}
    $CONTAINER_COMMAND cp $(docker create --name hypershift --rm --pull always $HYPERSHIFT_IMAGE):/usr/bin/hypershift /tmp/hypershift
    $CONTAINER_COMMAND rm -f hypershift

    # Install the hypershift binary
    sudo install -m 0755 -o root -g root /tmp/hypershift /usr/local/bin/hypershift
    rm -f /tmp/hypershift

    # Install the Hypershift operator
    KUBECONFIG=$KUBECONFIG hypershift install --hypershift-image $HYPERSHIFT_IMAGE

    # Check the Hypershift operator status
    log "Checking Hypershift operator status..."
    KUBECONFIG=$KUBECONFIG oc -n hypershift get pods

    log "Hypershift installation completed successfully!"
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
