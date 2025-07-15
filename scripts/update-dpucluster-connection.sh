#!/bin/bash
# Script to update dpucluster to use new hosted cluster kubeconfig

set -e
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

echo "=== Updating DPU Cluster Connection to New Hosted Cluster ==="

# Step 1: Delete old dpucluster and secret
echo "1. Cleaning up old dpucluster configuration..."
oc delete dpucluster ${HOSTED_CLUSTER_NAME} -n dpf-operator-system --ignore-not-found=true || \
    oc delete dpucluster cluster -n dpf-operator-system --ignore-not-found=true

echo "2. Deleting old kubeconfig secrets..."
oc delete secret ${HOSTED_CLUSTER_NAME}-kubeconfig -n dpf-operator-system --ignore-not-found=true
oc delete secret ${HOSTED_CLUSTER_NAME}-admin-kubeconfig -n dpf-operator-system --ignore-not-found=true

# Wait a bit for cleanup
echo "3. Waiting for cleanup..."
sleep 10

# Step 2: Generate new kubeconfig
echo "4. Generating new kubeconfig for hosted cluster..."
hypershift create kubeconfig \
    --namespace="${CLUSTERS_NAMESPACE}" \
    --name="${HOSTED_CLUSTER_NAME}" > ${HOSTED_CLUSTER_NAME}.kubeconfig

# Verify kubeconfig is valid
if ! grep -q "apiVersion: v1" ${HOSTED_CLUSTER_NAME}.kubeconfig || ! grep -q "kind: Config" ${HOSTED_CLUSTER_NAME}.kubeconfig; then
    echo "ERROR: Generated kubeconfig is invalid"
    exit 1
fi

echo "5. Testing new kubeconfig..."
if KUBECONFIG=${HOSTED_CLUSTER_NAME}.kubeconfig oc get co &>/dev/null; then
    echo "✓ Kubeconfig is valid and can access hosted cluster"
else
    echo "✗ Cannot access hosted cluster with new kubeconfig"
    exit 1
fi

# Step 3: Create new secret
echo "6. Creating new kubeconfig secret..."
oc create secret generic ${HOSTED_CLUSTER_NAME}-kubeconfig \
    -n dpf-operator-system \
    --from-file=kubeconfig=${HOSTED_CLUSTER_NAME}.kubeconfig

# Step 4: Create new dpucluster
echo "7. Creating new DPU cluster object..."
cat <<EOF | oc apply -f -
apiVersion: idms.nvidia.com/v1alpha1
kind: DPUCluster
metadata:
  name: ${HOSTED_CLUSTER_NAME}
  namespace: dpf-operator-system
spec:
  kubeConfigSecret:
    name: ${HOSTED_CLUSTER_NAME}-kubeconfig
    namespace: dpf-operator-system
EOF

# Wait for dpucluster to be ready
echo "8. Waiting for DPU cluster to be ready..."
count=0
while [ $count -lt 60 ]; do
    if oc get dpucluster ${HOSTED_CLUSTER_NAME} -n dpf-operator-system -o jsonpath='{.status.phase}' | grep -q "Ready"; then
        echo "✓ DPU cluster is ready"
        break
    fi
    echo -n "."
    sleep 5
    count=$((count + 5))
done

# Step 5: Verify
echo -e "\n9. Verification:"
echo "DPU Cluster status:"
oc get dpucluster -A -o wide

echo -e "\nDPU Cluster creation time:"
oc get dpucluster ${HOSTED_CLUSTER_NAME} -n dpf-operator-system -o jsonpath='{.metadata.creationTimestamp}'
echo

echo -e "\n✓ DPU cluster has been updated to use the new hosted cluster kubeconfig"