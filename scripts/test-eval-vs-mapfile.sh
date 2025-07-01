#!/bin/bash
# Test script to compare eval vs mapfile approaches
set -euo pipefail

# Mock JSON data for testing
mock_json() {
    cat <<'EOF'
{
  "items": [
    {"metadata": {"name": "master-0"}, "spec": {"podCIDR": "10.244.1.0/24"}},
    {"metadata": {"name": "worker-0"}, "spec": {"podCIDR": "10.244.3.0/24"}},
    {"metadata": {"name": "worker-1"}, "spec": {"podCIDR": "10.244.5.0/24"}},
    {"metadata": {"name": "worker-2"}, "spec": {}},
    {"metadata": {"name": "worker-3"}, "spec": {}},
    {"metadata": {"name": "worker-4"}, "spec": {}}
  ]
}
EOF
}

echo "=== Testing eval approach ==="
# Current approach with eval
json_data=$(mock_json)
eval $(echo "$json_data" | jq -r '
  .items | {
    used: [.[] | .spec.podCIDR // empty | match("10.244.(\\d+).0").captures[0].string | tonumber] | sort,
    nodes: [.[] | select(.spec.podCIDR == null) | .metadata.name] | join(" ")
  } | "used_subnets=(\(.used | @sh)); nodes_to_patch=\"\(.nodes)\""')

echo "Used subnets (eval): ${used_subnets[@]}"
echo "Nodes to patch (eval): $nodes_to_patch"
echo "Number of nodes to patch: $(echo $nodes_to_patch | wc -w)"

# Save eval results for comparison
eval_subnets=("${used_subnets[@]}")
eval_nodes="$nodes_to_patch"

echo
echo "=== Testing mapfile approach ==="
# New approach with mapfile
json_data=$(mock_json)
mapfile -t used_subnets < <(
  echo "$json_data" | jq -r '
    .items[]
    | .spec.podCIDR // empty
    | match("10.244.(\\d+).0").captures[0].string
    | tonumber
  ' | sort -n
)

mapfile -t nodes_to_patch < <(
  echo "$json_data" | jq -r '
    .items[]
    | select(.spec.podCIDR == null)
    | .metadata.name
  '
)

echo "Used subnets (mapfile): ${used_subnets[@]}"
echo "Nodes to patch (mapfile): ${nodes_to_patch[@]}"
echo "Number of nodes to patch: ${#nodes_to_patch[@]}"

echo
echo "=== Comparison ==="
# Compare results
if [[ "${used_subnets[*]}" == "${eval_subnets[*]}" ]]; then
    echo "✓ Used subnets match"
else
    echo "✗ Used subnets differ!"
    echo "  eval: ${eval_subnets[*]}"
    echo "  mapfile: ${used_subnets[*]}"
fi

# Compare nodes (need to normalize since one is string, other is array)
mapfile_nodes_str="${nodes_to_patch[*]}"
if [[ "$mapfile_nodes_str" == "$eval_nodes" ]]; then
    echo "✓ Nodes to patch match"
else
    echo "✗ Nodes to patch differ!"
    echo "  eval: $eval_nodes"
    echo "  mapfile: $mapfile_nodes_str"
fi

echo
echo "=== Testing edge cases ==="
# Test with no nodes needing patches
echo '{"items": [{"metadata": {"name": "node1"}, "spec": {"podCIDR": "10.244.1.0/24"}}]}' | jq -r '.items[] | select(.spec.podCIDR == null) | .metadata.name' | wc -l
echo "Empty nodes test: $(echo '{"items": [{"metadata": {"name": "node1"}, "spec": {"podCIDR": "10.244.1.0/24"}}]}' | jq -r '.items[] | select(.spec.podCIDR == null) | .metadata.name' | wc -l) nodes"

# Test array handling in loops
echo
echo "=== Loop test with mapfile arrays ==="
for node in "${nodes_to_patch[@]}"; do
    echo "Would patch: $node"
done