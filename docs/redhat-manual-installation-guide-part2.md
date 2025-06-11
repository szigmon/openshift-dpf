# Red Hat Manual Installation Guide: NVIDIA DPF on OpenShift (Part 2)

## Network Services Configuration (Continued)

### Step 2: Deploy OVN-Kubernetes DPU Service

```bash
# Create OVN credentials secret
cat << EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ovn-dpu
  namespace: dpf-operator-system
type: Opaque
data:
  # Base64 encoded kubeconfig for hosted cluster
  admin.conf: $(cat ${HOSTED_CLUSTER_NAME}.kubeconfig | base64 -w 0)
EOF

# Create OVN DPU Service
cat << EOF | oc apply -f -
apiVersion: svc.dpu.nvidia.com/v1alpha1
kind: DPUService
metadata:
  name: ovn-dpu
  namespace: dpf-operator-system
spec:
  helmChart:
    source:
      chart: ovn-kubernetes-chart
      repoURL: oci://ghcr.io/nvidia
      version: ${DPF_VERSION}
    values:
      global:
        gatewayOpts: --gateway-interface=br-ovn --gateway-uplink-port=puplinkbrovn
        imagePullSecretName: dpf-pull-secret
      k8sAPIServer: https://${HOST_CLUSTER_API}:6443
      mtu: 1400
      ovnkube-node-dpu:
        cniBinDir: /var/lib/cni/bin/
        cniConfDir: /run/multus/cni/net.d
        hostCIDR: ${POD_CIDR}
        ipamPFIPIndex: 1
        ipamPool: pool1
        ipamPoolType: cidrpool
        ipamVTEPIPIndex: 0
        kubernetesSecretName: ovn-dpu
        vtepCIDR: ${HBN_OVN_NETWORK}
      podNetwork: ${POD_CIDR}
      serviceNetwork: ${SERVICE_CIDR}
      tags:
        ovn-kubernetes-resource-injector: false
        ovnkube-control-plane: false
        ovnkube-node-dpu: true
        ovnkube-node-dpu-host: false
        ovnkube-single-node-zone: false
EOF
```

### Step 3: Configure Network Interfaces

```bash
# Create physical interfaces configuration
cat << EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: physical-ifaces
  namespace: dpf-operator-system
data:
  interfaces.yaml: |
    interfaces:
      - name: p0
        spec:
          physicalNetwork: provider
          switchID: p0
          type: sf
      - name: p1
        spec:
          physicalNetwork: provider
          switchID: p1
          type: sf
      - name: pf0hpf
        spec:
          physicalNetwork: provider
          switchID: pf0hpf
          type: sf
      - name: app-sf
        spec:
          type: sf
EOF

# Apply interface configuration
oc apply -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ovn-ifaces
  namespace: dpf-operator-system
data:
  interfaces.yaml: |
    interfaces:
      - name: pf0hpf
        spec:
          interfaceType: ovn-bridge-port
          bridge: br-ovn
EOF
```

### Step 4: Deploy HBN (Host-Based Networking) Service

```bash
# Create HBN interfaces configuration
cat << EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: hbn-ifaces
  namespace: dpf-operator-system
data:
  interfaces.yaml: |
    interfaces:
      - name: p0-sf
        spec:
          interfaceType: bridge-port-sub-function
          bridge: br-hbn
          hwAddr: 02:02:02:02:02:02
          pfIndex: 0
          sfIndex: 0
          representorPortName: pf0sf0
      - name: p1-sf
        spec:
          interfaceType: bridge-port-sub-function
          bridge: br-hbn
          hwAddr: 02:02:02:02:02:03
          pfIndex: 1
          sfIndex: 0
          representorPortName: pf1sf0
      - name: app-sf
        spec:
          interfaceType: bridge-port-sub-function
          bridge: br-hbn
          hwAddr: 02:02:02:02:02:04
          pfIndex: 0
          sfIndex: 1
          representorPortName: pf0sf1
EOF

# Create HBN IPAM pools
cat << EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: hbn-ovn-ipam
  namespace: dpf-operator-system
data:
  ipam.yaml: |
    pools:
      - name: pool1
        type: cidrpool
        cidr: ${HBN_OVN_NETWORK}
        gateway: $(echo ${HBN_OVN_NETWORK} | sed 's|0/22|1|')
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: hbn-loopback-ipam
  namespace: dpf-operator-system
data:
  ipam.yaml: |
    pools:
      - name: loopback
        type: cidrpool
        cidr: 127.0.0.0/8
EOF

# Deploy HBN DPU Service
cat << EOF | oc apply -f -
apiVersion: svc.dpu.nvidia.com/v1alpha1
kind: DPUService
metadata:
  name: doca-hbn
  namespace: dpf-operator-system
spec:
  serviceID: doca-hbn
  interfaces:
  - p0-sf
  - p1-sf
  - app-sf
  serviceDaemonSet:
    annotations:
      k8s.v1.cni.cncf.io/networks: |
        [
          {"name": "iprequest", "interface": "ip_lo", "cni-args": {"poolNames": ["loopback"], "poolType": "cidrpool"}},
          {"name": "iprequest", "interface": "ip_pf2dpu2", "cni-args": {"poolNames": ["pool1"], "poolType": "cidrpool", "allocateDefaultGateway": true}}
        ]
  helmChart:
    source:
      repoURL: https://helm.ngc.nvidia.com/nvidia/doca
      version: 1.0.1
      chart: doca-hbn
    values:
      image:
        repository: quay.io/itsoiref/hbn
        tag: 24-fix
      resources:
        memory: 6Gi
        nvidia.com/bf_sf: 3
      configuration:
        perDPUValuesYAML: |
          - hostnamePattern: "*"
            values:
              bgp_peer_group: hbn
          - hostnamePattern: "nvd-srv-24*"
            values:
              bgp_autonomous_system: 65101
          - hostnamePattern: "nvd-srv-25*"
            values:
              bgp_autonomous_system: 65201
        startupYAMLJ2: |
          - header:
              model: BLUEFIELD
              nvue-api-version: nvue_v1
              rev-id: 1.0
              version: HBN 2.4.0
          - set:
              interface:
                lo:
                  ip:
                    address:
                      {{ ipaddresses.ip_lo.ip }}/32: {}
                  type: loopback
                p0_if,p1_if:
                  type: swp
                  link:
                    mtu: 9000
                pf2dpu2_if:
                  ip:
                    address:
                      {{ ipaddresses.ip_pf2dpu2.cidr }}: {}
                  type: swp
                  link:
                    mtu: 9000
              router:
                bgp:
                  autonomous-system: {{ config.bgp_autonomous_system }}
                  enable: on
                  graceful-restart:
                    mode: full
                  router-id: {{ ipaddresses.ip_lo.ip }}
              vrf:
                default:
                  router:
                    bgp:
                      address-family:
                        ipv4-unicast:
                          enable: on
                          redistribute:
                            connected:
                              enable: on
                        ipv6-unicast:
                          enable: on
                          redistribute:
                            connected:
                              enable: on
                      enable: on
                      neighbor:
                        p0_if:
                          peer-group: {{ config.bgp_peer_group }}
                          type: unnumbered
                        p1_if:
                          peer-group: {{ config.bgp_peer_group }}
                          type: unnumbered
                      path-selection:
                        multipath:
                          aspath-ignore: on
                      peer-group:
                        {{ config.bgp_peer_group }}:
                          remote-as: external
EOF
```

### Step 5: Configure Service Function Chaining

```bash
# Create Service Function Chain for OVN to HBN traffic
cat << EOF | oc apply -f -
apiVersion: sfc.dpu.nvidia.com/v1alpha1
kind: ServiceFunctionChain
metadata:
  name: hbn-ovn-chain
  namespace: dpf-operator-system
spec:
  switches:
    - name: br-ovn
      ports:
        - name: puplinkbrovn
          serviceFunction: doca-hbn
          representor: pf0sf1
    - name: br-hbn
      ports:
        - name: pdownlinkbrhbn
          serviceFunction: ovn-dpu
          representor: pf0sf1
  chains:
    - name: ovn-to-hbn
      path:
        - switch: br-ovn
          port: puplinkbrovn
          direction: egress
        - switch: br-hbn
          port: pdownlinkbrhbn
          direction: ingress
    - name: hbn-to-ovn
      path:
        - switch: br-hbn
          port: pdownlinkbrhbn
          direction: egress
        - switch: br-ovn
          port: puplinkbrovn
          direction: ingress
EOF
```

### Step 6: Configure Network Policies

```bash
# Create network policy for DPU services
cat << EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dpu-services-policy
  namespace: dpf-operator-system
spec:
  podSelector:
    matchLabels:
      dpu.nvidia.com/service: "true"
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: dpf-operator-system
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: dpf-operator-system
  - to: []
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 6443
EOF
```

## Verification and Testing

### Step 1: Verify Operator Installation

```bash
# Check DPF operator status
oc get deployment -n dpf-operator-system
oc get pods -n dpf-operator-system

# Verify operator logs
oc logs -n dpf-operator-system deployment/dpf-operator-controller-manager

# Check DPF operator configuration
oc get dpfoperatorconfig -n dpf-operator-system -o yaml
```

### Step 2: Verify Hosted Cluster

```bash
# Check hosted cluster status
oc get hostedcluster -n ${CLUSTERS_NAMESPACE}
oc get hostedcontrolplane -n ${HOSTED_CONTROL_PLANE_NAMESPACE}

# Verify hosted cluster is accessible
export KUBECONFIG=${HOSTED_CLUSTER_NAME}.kubeconfig
oc get nodes
oc get pods -A

# Switch back to management cluster
export KUBECONFIG=./${CLUSTER_NAME}-kubeconfig
```

### Step 3: Verify DPU Provisioning

```bash
# Check DPU nodes detection
oc get nodes -l feature.node.kubernetes.io/dpu-enabled=true

# Verify DPU resources
oc get dpuset -n dpf-operator-system
oc get dpu -n dpf-operator-system
oc get dpucluster -n dpf-operator-system

# Check DPU provisioning status
oc describe dpuset dpuset -n dpf-operator-system

# Verify BFB resources
oc get bfb -n dpf-operator-system
oc get pvc bfb-pvc -n dpf-operator-system
```

### Step 4: Verify Network Services

```bash
# Check DPU services
oc get dpuservice -n dpf-operator-system
oc describe dpuservice ovn-dpu -n dpf-operator-system
oc describe dpuservice doca-hbn -n dpf-operator-system

# Verify Service Function Chains
oc get servicefunctionchain -n dpf-operator-system
oc describe servicefunctionchain hbn-ovn-chain -n dpf-operator-system

# Check SR-IOV configuration
oc get sriovnetworknodepolicy -n openshift-sriov-network-operator
oc get sriovnetwork -n openshift-sriov-network-operator
```

### Step 5: Network Connectivity Testing

```bash
# Test OVN-Kubernetes connectivity
export KUBECONFIG=${HOSTED_CLUSTER_NAME}.kubeconfig

# Create test pod
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  namespace: default
spec:
  containers:
  - name: test
    image: registry.redhat.io/ubi8/ubi:latest
    command: ["/bin/sleep", "3600"]
EOF

# Test pod connectivity
oc exec network-test -- ping -c 3 8.8.8.8
oc exec network-test -- nslookup kubernetes.default.svc.cluster.local

# Switch back to management cluster
export KUBECONFIG=./${CLUSTER_NAME}-kubeconfig
```

### Step 6: Performance Validation

```bash
# Check DPU resource utilization
oc get nodes -l feature.node.kubernetes.io/dpu-enabled=true -o custom-columns="NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory"

# Verify SR-IOV VF allocation
oc get sriovnetworknodestate -n openshift-sriov-network-operator

# Check OVS configuration on DPUs
oc debug node/<DPU_NODE_NAME> -- chroot /host ovs-vsctl show
oc debug node/<DPU_NODE_NAME> -- chroot /host ovs-vsctl list bridge
```

## Day 2 Operations

### Upgrading DPF Components

#### Upgrade DPF Operator

```bash
# Update DPF operator to new version
export NEW_DPF_VERSION="v25.5.0"  # Replace with desired version

helm upgrade dpf-operator \
  "https://helm.ngc.nvidia.com/nvidia/doca/charts/dpf-operator-${NEW_DPF_VERSION}.tgz" \
  --namespace dpf-operator-system \
  --reuse-values

# Wait for upgrade completion
oc rollout status deployment/dpf-operator-controller-manager -n dpf-operator-system
```

#### Update DPU Services

```bash
# Update OVN DPU service
oc patch dpuservice ovn-dpu -n dpf-operator-system --type=merge -p '{
  "spec": {
    "helmChart": {
      "source": {
        "version": "'"${NEW_DPF_VERSION}"'"
      }
    }
  }
}'

# Monitor service update
oc get pods -n dpf-operator-system -l dpu.nvidia.com/service=ovn-dpu -w
```

### Managing DPU Lifecycle

#### Adding New DPU Nodes

```bash
# Label new nodes with DPU capability
oc label node <NEW_NODE_NAME> feature.node.kubernetes.io/dpu-enabled=true

# Verify DPU detection
oc get nodes -l feature.node.kubernetes.io/dpu-enabled=true

# DPUSet will automatically provision new DPUs
oc get dpu -n dpf-operator-system -w
```

#### Replacing DPU Nodes

```bash
# Drain the DPU node
oc drain <DPU_NODE_NAME> --ignore-daemonsets --delete-emptydir-data

# Remove DPU from cluster
oc delete dpu <DPU_NAME> -n dpf-operator-system

# Remove node from cluster
oc delete node <DPU_NODE_NAME>

# Add replacement node and label it
oc label node <NEW_DPU_NODE_NAME> feature.node.kubernetes.io/dpu-enabled=true
```

### Monitoring and Troubleshooting

#### Monitoring DPF Health

```bash
# Monitor DPF operator health
oc get deployment -n dpf-operator-system -w
oc get pods -n dpf-operator-system -w

# Check DPU status
oc get dpu -n dpf-operator-system -o wide
oc get dpuservice -n dpf-operator-system -o wide

# Monitor hosted cluster health
oc get hostedcluster -n ${CLUSTERS_NAMESPACE} -w
```

#### Common Troubleshooting Commands

```bash
# Check DPU provisioning issues
oc describe dpuset dpuset -n dpf-operator-system
oc logs -n dpf-operator-system -l app.kubernetes.io/name=dpf-provisioning-controller

# Debug network service issues
oc logs -n dpf-operator-system -l dpu.nvidia.com/service=ovn-dpu
oc logs -n dpf-operator-system -l dpu.nvidia.com/service=doca-hbn

# Check BFB download issues
oc describe bfb bf-bundle -n dpf-operator-system
oc logs -n dpf-operator-system -l app.kubernetes.io/name=dpf-provisioning-controller | grep bfb

# Verify SR-IOV configuration
oc get sriovnetworknodestate -n openshift-sriov-network-operator -o yaml
oc logs -n openshift-sriov-network-operator -l app=sriov-network-operator
```

#### Log Collection

```bash
# Collect DPF operator logs
oc logs -n dpf-operator-system deployment/dpf-operator-controller-manager > dpf-operator.log

# Collect all DPU service logs
for service in $(oc get dpuservice -n dpf-operator-system -o name); do
  oc logs -n dpf-operator-system -l "dpu.nvidia.com/service=${service##*/}" > "${service##*/}.log"
done

# Collect hosted cluster logs
oc logs -n ${HOSTED_CONTROL_PLANE_NAMESPACE} -l app=kube-apiserver > hosted-cluster-apiserver.log
oc logs -n ${HOSTED_CONTROL_PLANE_NAMESPACE} -l app=etcd > hosted-cluster-etcd.log
```

### Backup and Recovery

#### Backup Hosted Cluster

```bash
# Backup hosted cluster configuration
oc get hostedcluster ${HOSTED_CLUSTER_NAME} -n ${CLUSTERS_NAMESPACE} -o yaml > hosted-cluster-backup.yaml
oc get hostedcontrolplane ${HOSTED_CLUSTER_NAME} -n ${HOSTED_CONTROL_PLANE_NAMESPACE} -o yaml > hosted-controlplane-backup.yaml

# Backup DPF configuration
oc get dpfoperatorconfig -n dpf-operator-system -o yaml > dpf-config-backup.yaml
oc get dpuset -n dpf-operator-system -o yaml > dpuset-backup.yaml
```

#### Recovery Procedures

```bash
# Restore hosted cluster (if needed)
oc apply -f hosted-cluster-backup.yaml
oc apply -f hosted-controlplane-backup.yaml

# Restore DPF configuration
oc apply -f dpf-config-backup.yaml
oc apply -f dpuset-backup.yaml

# Verify restoration
oc get hostedcluster -n ${CLUSTERS_NAMESPACE}
oc get dpuset -n dpf-operator-system
```

## Conclusion

This manual installation guide provides comprehensive instructions for deploying NVIDIA DPF on Red Hat OpenShift using Hypershift and RHCOS. The key differences from NVIDIA's standard approach include:

- **Hypershift instead of Kamaji** for hosted cluster management
- **RHCOS instead of Ubuntu** on BlueField DPUs  
- **OpenShift-native storage** (ODF/LVM) integration
- **Red Hat operator ecosystem** integration

### Key Benefits

- **Enterprise Support**: Full Red Hat support for the entire stack
- **Security**: Leverages OpenShift security features and RHCOS hardening
- **Scalability**: Hypershift provides better multi-cluster management capabilities
- **Integration**: Native integration with OpenShift monitoring, logging, and management tools

### Next Steps

- **Production Deployment**: Scale the installation for production workloads
- **Monitoring Integration**: Configure Prometheus monitoring for DPF components
- **CI/CD Integration**: Implement GitOps workflows for DPF service management
- **Performance Tuning**: Optimize DPU configurations for specific workloads

For additional support and advanced configurations, consult the Red Hat OpenShift documentation and NVIDIA DPF documentation. 