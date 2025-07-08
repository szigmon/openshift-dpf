#!/bin/bash
# dpf-upgrade.sh - Simple wrapper for DPF upgrade operations

# Exit on error
set -e

# Source environment
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# Display upgrade info
echo "🔄 DPF Operator Install/Upgrade"
echo "========================================"
echo "Target Version: $DPF_VERSION"
echo "Chart Source:   $DPF_HELM_REPO_URL-$DPF_VERSION.tgz"
echo "Namespace:      dpf-operator-system"
echo ""

# Check if interactive mode
if [ "${1:-interactive}" = "interactive" ]; then
    read -p "❓ Do you want to proceed? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "❌ Cancelled by user"
        exit 0
    fi
fi

echo ""
echo "🚀 Running DPF deployment..."
echo ""

# Just call the existing scripts
if ! make -C "$(dirname "${BASH_SOURCE[0]}")/.." prepare-dpf-manifests; then
    echo "❌ Failed to prepare DPF manifests"
    exit 1
fi

echo ""
echo "✅ DPF operator installation completed!"
echo ""