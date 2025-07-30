#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Installing MCE with Pre-pulled Bundle ==="
echo ""

# Step 1: Find the MCE bundle image
echo "1. Finding MCE bundle image for stable-2.8..."
BUNDLE_INFO=$(oc get packagemanifest multicluster-engine -n openshift-marketplace -o json | jq -r '.status.channels[] | select(.name=="stable-2.8")')
BUNDLE_IMAGE=$(echo "$BUNDLE_INFO" | jq -r '.currentCSVDesc.annotations."operatorframework.io/bundle-image"' 2>/dev/null || echo "")
CSV_NAME=$(echo "$BUNDLE_INFO" | jq -r '.currentCSV' 2>/dev/null || echo "")

if [ -z "$BUNDLE_IMAGE" ]; then
    echo "   Using default bundle image for MCE 2.8"
    BUNDLE_IMAGE="registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator-bundle:v2.8.4"
    CSV_NAME="multicluster-engine.v2.8.4"
fi

echo "   Bundle image: $BUNDLE_IMAGE"
echo "   CSV name: $CSV_NAME"

# Step 2: Pre-pull the bundle image to all nodes
echo ""
echo "2. Pre-pulling MCE bundle image on all nodes..."
cat > /tmp/mce-prepull-ds.yaml << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: mce-bundle-prepull
  namespace: openshift-operator-lifecycle-manager
spec:
  selector:
    matchLabels:
      name: mce-bundle-prepull
  template:
    metadata:
      labels:
        name: mce-bundle-prepull
    spec:
      tolerations:
      - operator: Exists
      initContainers:
      - name: prepull
        image: ${BUNDLE_IMAGE}
        command: ["/bin/sh", "-c", "echo 'Bundle image pulled successfully'"]
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
        resources:
          requests:
            cpu: 10m
            memory: 10Mi
EOF

oc apply -f /tmp/mce-prepull-ds.yaml

# Wait for all pods to be ready
echo "   Waiting for bundle to be pulled on all nodes..."
NODE_COUNT=$(oc get nodes --no-headers | wc -l)
pull_retries=60

while [ $pull_retries -gt 0 ]; do
    READY_COUNT=$(oc get pods -n openshift-operator-lifecycle-manager -l name=mce-bundle-prepull -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
    if [ "$READY_COUNT" -eq "$NODE_COUNT" ]; then
        echo "   ✓ Bundle pulled on all $NODE_COUNT nodes"
        break
    fi
    echo -n "."
    sleep 5
    ((pull_retries--))
done

# Clean up the DaemonSet
oc delete daemonset -n openshift-operator-lifecycle-manager mce-bundle-prepull --wait=false

# Step 3: Create ImageContentSourcePolicy for faster pulls
echo ""
echo "3. Creating ImageContentSourcePolicy for MCE..."
cat > /tmp/mce-icsp.yaml << EOF
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: mce-bundle-mirror
spec:
  repositoryDigestMirrors:
  - mirrors:
    - registry.redhat.io
    source: registry.redhat.io/multicluster-engine
EOF

oc apply -f /tmp/mce-icsp.yaml

# Step 4: Clean up any existing MCE resources
echo ""
echo "4. Cleaning up any existing MCE resources..."
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    oc delete subscription -n multicluster-engine multicluster-engine --wait=false
fi

# Step 5: Apply MCE operator
echo ""
echo "5. Installing MCE operator..."
oc apply -f manifests/cluster-installation/mce-operator.yaml

# Step 6: Monitor installation with detailed status
echo ""
echo "6. Monitoring MCE installation..."
echo "   Waiting for subscription to process..."
sleep 10

# Check subscription status
echo "   Subscription status:"
oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' || echo "Not ready"

# Wait for InstallPlan
echo ""
echo "   Waiting for InstallPlan..."
plan_retries=60
while [ $plan_retries -gt 0 ]; do
    INSTALLPLAN=$(oc get installplan -n multicluster-engine -o name 2>/dev/null | head -1)
    if [ -n "$INSTALLPLAN" ]; then
        echo "   ✓ InstallPlan created: $INSTALLPLAN"
        
        # Approve it if needed
        APPROVAL=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.spec.approved}')
        if [ "$APPROVAL" != "true" ]; then
            echo "   Approving InstallPlan..."
            oc patch $INSTALLPLAN -n multicluster-engine --type merge -p '{"spec":{"approved":true}}'
        fi
        
        # Wait for completion
        echo "   Waiting for InstallPlan to complete..."
        complete_retries=120
        while [ $complete_retries -gt 0 ]; do
            PHASE=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.phase}')
            if [ "$PHASE" = "Complete" ]; then
                echo "   ✓ InstallPlan completed!"
                break
            elif [ "$PHASE" = "Failed" ]; then
                echo "   ✗ InstallPlan failed!"
                oc get $INSTALLPLAN -n multicluster-engine -o yaml
                exit 1
            fi
            echo -n "."
            sleep 5
            ((complete_retries--))
        done
        break
    fi
    echo -n "."
    sleep 5
    ((plan_retries--))
done

# Step 7: Wait for CSV
echo ""
echo "7. Waiting for MCE operator to be ready..."
csv_retries=60
while [ $csv_retries -gt 0 ]; do
    if oc get csv -n multicluster-engine $CSV_NAME &>/dev/null; then
        PHASE=$(oc get csv -n multicluster-engine $CSV_NAME -o jsonpath='{.status.phase}')
        if [ "$PHASE" = "Succeeded" ]; then
            echo "   ✓ MCE operator is ready!"
            break
        fi
    fi
    echo -n "."
    sleep 5
    ((csv_retries--))
done

# Step 8: Enable HyperShift
echo ""
echo "8. Enabling HyperShift in MCE..."
oc apply -f manifests/cluster-installation/mce-hypershift-config.yaml

# Step 9: Verify deployment
echo ""
echo "9. Verifying HyperShift deployment..."
wait_for_namespace "hypershift" 30 5
wait_for_pods "hypershift" "app=operator" "status.phase=Running" "1/1" 60 5

echo ""
echo "✓ MCE installed successfully with HyperShift enabled!"
echo ""
echo "Status:"
oc get mce -n multicluster-engine
oc get pods -n hypershift
echo ""
echo "You can now create the HostedCluster with: make deploy-hosted-cluster"