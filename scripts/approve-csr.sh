#!/bin/bash
# Script to auto-approve CSRs in the hosted cluster

set -e

# Check if kubeconfig is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <kubeconfig-file>"
    echo "Example: $0 doca-hcp.kubeconfig"
    exit 1
fi

export KUBECONFIG=$1

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Auto-approving CSRs for kubeconfig: $KUBECONFIG${NC}"
echo "Press Ctrl+C to stop"
echo

# Function to approve pending CSRs
approve_pending_csrs() {
    local pending=$(oc get csr -o json | jq -r '.items[] | select(.status.conditions == null or (.status.conditions | map(select(.type == "Approved")) | length == 0)) | .metadata.name')
    
    if [ -n "$pending" ]; then
        echo -e "${YELLOW}Found pending CSRs:${NC}"
        echo "$pending"
        
        for csr in $pending; do
            echo -e "${GREEN}Approving CSR: $csr${NC}"
            oc adm certificate approve $csr
        done
        return 0
    else
        return 1
    fi
}

# Main loop
while true; do
    if approve_pending_csrs; then
        echo "---"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S'): No pending CSRs"
    fi
    
    # Show current nodes count
    node_count=$(oc get nodes --no-headers 2>/dev/null | wc -l)
    echo "Current nodes: $node_count"
    
    # Show node names and status
    if [ $node_count -gt 0 ]; then
        oc get nodes --no-headers | awk '{printf "  - %s (%s)\n", $1, $2}'
    fi
    
    echo "---"
    sleep 30
done