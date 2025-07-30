#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=== Manual MCE CSV Installation ==="
echo ""
echo "This approach bypasses OLM bundle unpacking by creating the CSV directly"
echo ""

# Step 1: Extract MCE information from catalog
echo "1. Extracting MCE information from catalog..."
CATALOG_INFO=$(oc get packagemanifest multicluster-engine -o json)
CHANNEL_INFO=$(echo "$CATALOG_INFO" | jq -r '.status.channels[] | select(.name=="stable-2.8")')
CSV_NAME=$(echo "$CHANNEL_INFO" | jq -r '.currentCSV')
CSV_VERSION=$(echo "$CSV_NAME" | sed 's/multicluster-engine.v//')

echo "   CSV Name: $CSV_NAME"
echo "   Version: $CSV_VERSION"

# Step 2: Create namespace and prerequisites
echo ""
echo "2. Creating prerequisites..."
oc apply -f - << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: multicluster-engine
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine-operatorgroup
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
EOF

# Step 3: Create service accounts and RBAC
echo ""
echo "3. Creating RBAC resources..."
oc apply -f - << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: multicluster-engine-operator
  namespace: multicluster-engine
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: multicluster-engine-operator
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: multicluster-engine-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: multicluster-engine-operator
subjects:
- kind: ServiceAccount
  name: multicluster-engine-operator
  namespace: multicluster-engine
EOF

# Step 4: Create the deployment
echo ""
echo "4. Creating MCE operator deployment..."
cat > /tmp/mce-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multicluster-engine-operator
  namespace: multicluster-engine
spec:
  replicas: 1
  selector:
    matchLabels:
      name: multicluster-engine-operator
  template:
    metadata:
      labels:
        name: multicluster-engine-operator
    spec:
      serviceAccountName: multicluster-engine-operator
      containers:
      - name: multicluster-engine-operator
        image: registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator:v${CSV_VERSION}
        imagePullPolicy: Always
        env:
        - name: WATCH_NAMESPACE
          value: "multicluster-engine"
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: OPERATOR_NAME
          value: "multicluster-engine-operator"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

oc apply -f /tmp/mce-deployment.yaml

# Step 5: Create the CSV
echo ""
echo "5. Creating MCE CSV..."
cat > /tmp/mce-csv.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: ClusterServiceVersion
metadata:
  name: ${CSV_NAME}
  namespace: multicluster-engine
spec:
  displayName: MultiCluster Engine for Kubernetes
  description: |
    Red Hat Advanced Cluster Management for Kubernetes provides the multicluster hub, a central management console for managing multiple Kubernetes-based clusters across data centers, public clouds, and private clouds.
  version: ${CSV_VERSION}
  replaces: multicluster-engine.v2.7.0
  maturity: stable
  maintainers:
  - email: acm-contact@redhat.com
    name: Red Hat
  provider:
    name: Red Hat
  installModes:
  - supported: true
    type: OwnNamespace
  - supported: false
    type: SingleNamespace
  - supported: false
    type: MultiNamespace
  - supported: false
    type: AllNamespaces
  install:
    strategy: deployment
    spec:
      deployments:
      - name: multicluster-engine-operator
        spec:
          replicas: 1
          selector:
            matchLabels:
              name: multicluster-engine-operator
          template:
            metadata:
              labels:
                name: multicluster-engine-operator
            spec:
              serviceAccountName: multicluster-engine-operator
              containers:
              - name: multicluster-engine-operator
                image: registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator:v${CSV_VERSION}
      permissions:
      - serviceAccountName: multicluster-engine-operator
        rules:
        - apiGroups: ["*"]
          resources: ["*"]
          verbs: ["*"]
      clusterPermissions:
      - serviceAccountName: multicluster-engine-operator
        rules:
        - apiGroups: ["*"]
          resources: ["*"]
          verbs: ["*"]
  customresourcedefinitions:
    owned:
    - name: multiclusterengines.multicluster.openshift.io
      version: v1
      kind: MultiClusterEngine
      displayName: MultiClusterEngine
      description: MultiClusterEngine is the schema for the multiclusterengines API
EOF

oc apply -f /tmp/mce-csv.yaml

# Step 6: Wait for deployment to be ready
echo ""
echo "6. Waiting for MCE operator to be ready..."
wait_for_pods "multicluster-engine" "name=multicluster-engine-operator" "status.phase=Running" "1/1" 60 5

# Step 7: Create the MCE CR to enable HyperShift
echo ""
echo "7. Creating MCE instance with HyperShift enabled..."
oc apply -f manifests/cluster-installation/mce-hypershift-config.yaml

# Step 8: Monitor HyperShift deployment
echo ""
echo "8. Waiting for HyperShift to be deployed..."
hypershift_retries=60
while [ $hypershift_retries -gt 0 ]; do
    if oc get namespace hypershift &>/dev/null; then
        echo "   ✓ HyperShift namespace created"
        if oc get deployment -n hypershift hypershift-operator &>/dev/null || oc get deployment -n hypershift operator &>/dev/null; then
            echo "   ✓ HyperShift operator deployed!"
            break
        fi
    fi
    echo -n "."
    sleep 5
    ((hypershift_retries--))
done

if [ $hypershift_retries -eq 0 ]; then
    echo "   ✗ Timeout waiting for HyperShift"
    echo "   MCE may need additional configuration or permissions"
    exit 1
fi

# Step 9: Verify installation
echo ""
echo "9. Verifying installation..."
echo "   MCE Status:"
oc get mce -n multicluster-engine
echo ""
echo "   HyperShift Status:"
oc get pods -n hypershift

echo ""
echo "✓ Manual MCE installation completed!"
echo ""
echo "Note: This is a simplified installation. Some MCE features may not be available."
echo "You can now create the HostedCluster with: make deploy-hosted-cluster"