#!/bin/bash
# Configure Flannel podCIDR for worker nodes
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Use hosted cluster kubeconfig if available
[[ -f "${HOSTED_CLUSTER_NAME}.kubeconfig" ]] && export KUBECONFIG="${HOSTED_CLUSTER_NAME}.kubeconfig"

# Get all used subnets and nodes without CIDR in one pass
eval $(oc get nodes -o json | jq -r '
  .items | {
    used: [.[] | .spec.podCIDR // empty | match("10.244.(\\d+).0").captures[0].string | tonumber] | sort,
    nodes: [.[] | select(.spec.podCIDR == null) | .metadata.name] | join(" ")
  } | "used_subnets=(\(.used | @sh)); nodes_to_patch=\"\(.nodes)\""')

[[ -z "$nodes_to_patch" ]] && { log "INFO" "All nodes already configured"; exit 0; }

# Find next available subnet
subnet=1
for node in $nodes_to_patch; do
    while [[ " ${used_subnets[@]} " =~ " $subnet " ]]; do ((subnet++)); done
    oc patch node "$node" --type merge -p "{\"spec\":{\"podCIDR\":\"10.244.${subnet}.0/24\"}}"
    log "INFO" "Configured $node with 10.244.${subnet}.0/24"
    used_subnets+=($subnet)
    ((subnet++))
done