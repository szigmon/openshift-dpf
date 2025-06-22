# Custom OVN Kubernetes Chart for OpenShift

This is a custom version of the OVN Kubernetes chart v25.4.0 with configurable CNI paths for OpenShift compatibility.

## Changes from Original

1. Added configurable CNI paths in `values.yaml`:
   ```yaml
   dpuManifests:
     cniBinDir: "/opt/cni/bin"      # Can be overridden to /var/lib/cni/bin/
     cniConfDir: "/etc/cni/net.d"   # Can be overridden to /run/multus/cni/net.d
   ```

2. Updated `templates/dpu-manifests.yaml` to use template variables:
   - Line 828: `path: {{ .Values.dpuManifests.cniBinDir }}`
   - Line 857: `path: {{ .Values.dpuManifests.cniBinDir }}`
   - Line 860: `path: {{ .Values.dpuManifests.cniConfDir }}`

## Usage

To use with OpenShift-compatible paths:

```yaml
apiVersion: svc.dpu.nvidia.com/v1alpha1
kind: DPUServiceTemplate
metadata:
  name: ovn
  namespace: dpf-operator-system
spec:
  deploymentServiceName: "ovn"
  helmChart:
    source:
      repoURL: <your-registry>
      chart: ovn-kubernetes-chart-custom
      version: "v25.4.0-custom"
    values:
      dpuManifests:
        enabled: true
        cniBinDir: /var/lib/cni/bin/
        cniConfDir: /run/multus/cni/net.d
```

## Building and Publishing

```bash
# Package the chart
helm package /tmp/custom-ovn-chart

# Push to OCI registry
helm push ovn-kubernetes-chart-custom-v25.4.0-custom.tgz oci://<your-registry>
```