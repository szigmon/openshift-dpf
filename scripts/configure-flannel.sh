#!/bin/bash
# configure-flannel.sh - Configure flannel IPAM controller for automatic podCIDR assignment

# Exit on error
set -e
set -o pipefail

# Source utilities and post-install functions
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"
source "$(dirname "${BASH_SOURCE[0]}")/post-install.sh"

# Main execution
log [INFO] "Configuring flannel IPAM controller..."

# Ensure we have kubeconfig
get_kubeconfig

# Call the configure_flannel_nodes function from post-install.sh
configure_flannel_nodes

log [INFO] "Flannel configuration complete"