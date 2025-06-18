#!/bin/bash
#
# Configure Flannel podCIDR for worker nodes in OpenShift cluster
# This script assigns unique /24 subnets from 10.244.0.0/16 to nodes
# Run this after manually adding worker nodes to make them Ready
#

set -euo pipefail

# Source environment and utilities
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Function to configure flannel podCIDR for nodes
function configure_flannel_podcidr() {
    log [INFO] "Configuring Flannel podCIDR for cluster nodes..."
    
    # Get kubeconfig for hosted cluster if using Hypershift
    if [[ "${DPF_CLUSTER_TYPE}" == "hypershift" ]]; then
        if [[ -f "${HOSTED_CLUSTER_NAME}.kubeconfig" ]]; then
            local saved_kubeconfig="${KUBECONFIG}"
            export KUBECONFIG="${HOSTED_CLUSTER_NAME}.kubeconfig"
            log [INFO] "Using hosted cluster kubeconfig: ${KUBECONFIG}"
        else
            log [ERROR] "Hosted cluster kubeconfig not found: ${HOSTED_CLUSTER_NAME}.kubeconfig"
            log [ERROR] "Please ensure the hosted cluster is created and kubeconfig is available"
            exit 1
        fi
    fi
    
    # Get all nodes
    local nodes=$(oc get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    if [ -z "$nodes" ]; then
        log [ERROR] "No nodes found in the cluster"
        if [[ "${DPF_CLUSTER_TYPE}" == "hypershift" ]]; then
            export KUBECONFIG="${saved_kubeconfig}"
        fi
        exit 1
    fi
    
    # Convert to array
    local node_array=($nodes)
    local node_count=${#node_array[@]}
    log [INFO] "Found ${node_count} nodes in the cluster"
    
    # First, collect all existing podCIDRs to track used subnets
    local -A used_subnets
    local nodes_needing_config=()
    
    for node in "${node_array[@]}"; do
        local current_cidr=$(oc get node "${node}" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)
        if [ -n "$current_cidr" ]; then
            log [INFO] "Node ${node} already has podCIDR: ${current_cidr}"
            # Extract the third octet to track used subnets
            if [[ "$current_cidr" =~ ^10\.244\.([0-9]+)\.0/24$ ]]; then
                local subnet_num="${BASH_REMATCH[1]}"
                used_subnets[$subnet_num]=1
            fi
        else
            log [INFO] "Node ${node} needs podCIDR configuration"
            nodes_needing_config+=("$node")
        fi
    done
    
    # If no nodes need configuration, we're done
    if [ ${#nodes_needing_config[@]} -eq 0 ]; then
        log [INFO] "All nodes already have podCIDR configured"
        if [[ "${DPF_CLUSTER_TYPE}" == "hypershift" ]]; then
            export KUBECONFIG="${saved_kubeconfig}"
        fi
        return 0
    fi
    
    # Configure only nodes that don't have podCIDR
    local next_subnet=1
    for node in "${nodes_needing_config[@]}"; do
        # Find next available subnet
        while [[ -n "${used_subnets[$next_subnet]}" ]]; do
            next_subnet=$((next_subnet + 1))
            if [ $next_subnet -gt 254 ]; then
                log [ERROR] "Exhausted available subnets in 10.244.0.0/16"
                if [[ "${DPF_CLUSTER_TYPE}" == "hypershift" ]]; then
                    export KUBECONFIG="${saved_kubeconfig}"
                fi
                exit 1
            fi
        done
        
        local pod_cidr="10.244.${next_subnet}.0/24"
        log [INFO] "Assigning ${node} podCIDR: ${pod_cidr}"
        
        # Patch the node
        if oc patch node "${node}" --type merge -p "{\"spec\":{\"podCIDR\":\"${pod_cidr}\",\"podCIDRs\":[\"${pod_cidr}\"]}}" 2>/dev/null; then
            log [INFO] "Successfully patched node ${node} with podCIDR ${pod_cidr}"
            used_subnets[$next_subnet]=1
        else
            log [ERROR] "Failed to patch node ${node}"
        fi
        
        next_subnet=$((next_subnet + 1))
    done
    
    # Restore original kubeconfig if using Hypershift
    if [[ "${DPF_CLUSTER_TYPE}" == "hypershift" ]]; then
        export KUBECONFIG="${saved_kubeconfig}"
    fi
    
    log [INFO] "Flannel podCIDR configuration completed"
    log [INFO] "Configured ${#nodes_needing_config[@]} new node(s)"
    log [INFO] "Nodes should transition to Ready state once flannel pods restart"
}

# Show usage
function usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Configure Flannel podCIDR for worker nodes in the cluster."
    echo "This assigns unique /24 subnets from 10.244.0.0/16 range."
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Example:"
    echo "  $0"
    echo ""
    echo "Run this after manually adding worker nodes to fix flannel networking."
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log [ERROR] "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
    
    # Run the configuration
    configure_flannel_podcidr
fi