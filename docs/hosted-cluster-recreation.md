# Hosted Cluster Recreation Guide

This guide explains how to delete and recreate a hosted cluster without rebuilding the entire management cluster.

## Prerequisites

Before running the recreation process, ensure:

1. **Environment Variables Set**:
   ```bash
   export DPU_HOST_CIDR="10.6.135.0/24"  # Your DPU subnet
   ```

2. **Tools Installed**:
   - `oc` CLI logged into management cluster
   - `hypershift` CLI installed
   - `python3` available

3. **DPF Operator Running**:
   ```bash
   oc get pods -n dpf-operator-system
   ```

## Quick Start

### Option 1: Automated Recreation (Recommended)

```bash
# Run the complete recreation process
make recreate-hosted-cluster
```

This will:
- Delete the existing hosted cluster
- Clean up all DPU resources
- Create a new hosted cluster
- Configure DPF for the new cluster
- Redeploy DPUs

### Option 2: Manual Steps

```bash
# Step 1: Delete everything
make delete-hosted-cluster

# Step 2: Wait and verify cleanup
make hosted-cluster-status

# Step 3: Recreate hosted cluster
make deploy-hypershift

# Step 4: Configure DPF
make configure-hypershift-dpucluster

# Step 5: Redeploy DPUs
make redeploy-dpu
```

## Monitoring Progress

### Check Status
```bash
# Overall status
make hosted-cluster-status

# Watch DPU provisioning
watch -n2 'oc get dpu -A'

# Monitor operator logs
oc logs -n dpf-operator-system deployment/dpf-operator-controller-manager -f
```

### Approve CSRs
After DPUs start provisioning, approve CSRs in the hosted cluster:

```bash
# Auto-approve CSRs
make approve-csr-hosted

# Or manually
export KUBECONFIG=doca-hcp.kubeconfig
oc get csr -o name | grep Pending | xargs -r oc adm certificate approve
```

## What Gets Deleted

The recreation process removes:
- Hosted cluster (hostedcluster object)
- Control plane namespace
- All DPU instances
- All DPU deployments
- BFB configurations
- DPU cluster configuration
- Kubeconfig secrets
- Ignition templates

## What Gets Recreated

The process creates:
- New hosted cluster with same configuration
- New kubeconfig and secrets
- New ignition template with updated data
- DPU cluster configuration
- All DPU manifests with new bf.cfg

## Troubleshooting

### Cleanup Issues
If cleanup fails:
```bash
# Force delete stuck resources
oc delete dpu --all -A --force --grace-period=0
oc delete namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} --force --grace-period=0
```

### Hosted Cluster Not Ready
Check etcd pods:
```bash
oc get pods -n clusters-doca-hcp -l app=etcd
oc describe hostedcluster -n clusters doca-hcp
```

### DPUs Not Provisioning
Check bf.cfg generation:
```bash
oc get bfb -A
oc describe dpu -A | grep -A5 "Message:"
```

## Environment Variables

Key variables used:
- `HOSTED_CLUSTER_NAME`: Name of hosted cluster (default: doca-hcp)
- `CLUSTERS_NAMESPACE`: Namespace for hosted clusters (default: clusters)
- `DPU_HOST_CIDR`: Subnet for DPU hosts (required, e.g., 10.6.135.0/24)
- `BASE_DOMAIN`: Base domain for cluster
- `OCP_RELEASE_IMAGE`: OpenShift release image

## Recovery

If something goes wrong:
1. Run `make delete-hosted-cluster` to clean up
2. Fix any issues (permissions, resources, etc.)
3. Run `make recreate-hosted-cluster` again

The process is idempotent and can be safely rerun.