# DPF Cleanup Operations

This document describes the comprehensive DPF cleanup functionality that helps manage and remove all DPF components when needed.

## Overview

The DPF cleanup system provides automated cleanup operations that handle all the edge cases and manual steps that were previously required when removing DPF components from a cluster.

## Available Operations

### Complete DPF Cleanup

```bash
make cleanup-dpf
```

This is the main cleanup operation that performs a comprehensive removal of all DPF components:

1. **Interactive Confirmation**: Prompts user to confirm the destructive operation
2. **Scale Down**: Scales down all DPF deployments and statefulsets to 0 replicas
3. **Namespace Cleanup**: Removes all resources within the `dpf-operator-system` namespace
4. **Cluster Resources**: Removes cluster-wide resources (ClusterRoles, ClusterRoleBindings)
5. **Webhook Cleanup**: Removes ValidatingWebhookConfigurations and MutatingWebhookConfigurations
6. **Certificate Management**: Cleans up cert-manager resources (certificates, issuers)
7. **Custom Resources**: Removes MaintenanceOperatorConfig and other DPF custom resources
8. **Storage Cleanup**: Handles PVCs, PVs, and failed storage resources
9. **Helm Cleanup**: Uninstalls Helm releases
10. **CRD Removal**: Removes CRDs with proper finalizer handling
11. **Namespace Finalization**: Force finalizes namespace if stuck in Terminating state

### Force Namespace Cleanup

```bash
make force-cleanup-dpf-namespace
```

This operation specifically handles namespaces stuck in "Terminating" state by force finalizing them.

### Recreate Clean Namespace

```bash
make recreate-dpf-namespace
```

This operation waits for the namespace to be fully removed and then creates a fresh, clean namespace.

## What Gets Cleaned Up

### Namespaced Resources
- All deployments, statefulsets, daemonsets
- Pods, services, ingresses
- Secrets, configmaps, serviceaccounts
- Roles and rolebindings
- PVCs and associated PVs
- Custom resources (MaintenanceOperatorConfig, etc.)

### Cluster-Wide Resources
- ClusterRoles and ClusterRoleBindings matching `dpf|dpu` patterns
- ValidatingWebhookConfigurations and MutatingWebhookConfigurations
- CRDs with domains: `dpu.nvidia.com`, `dpf`, `maintenance.nvidia.com`
- ClusterIssuers (cert-manager)

### Storage Resources
- All PVCs in the `dpf-operator-system` namespace
- Failed/orphaned PVs related to DPF
- PVs in "Failed" state that were bound to the DPF namespace

### Helm Resources
- DPF operator Helm releases
- Any other Helm releases in the `dpf-operator-system` namespace

## Edge Cases Handled

The cleanup system specifically handles several edge cases that were encountered during development:

1. **Helm Ownership Conflicts**: Properly removes resources that might conflict with Helm ownership metadata
2. **Stuck Finalizers**: Force removes finalizers from CRDs and other resources
3. **Terminating Namespaces**: Force finalizes namespaces stuck in Terminating state
4. **Failed PVs**: Cleans up PVs that remain in Failed state after PVC deletion
5. **Orphaned Webhooks**: Removes webhook configurations that might block resource deletion
6. **Certificate Dependencies**: Properly removes cert-manager resources and their dependencies

## Direct Script Usage

The cleanup functionality can also be used directly:

```bash
# Complete cleanup
scripts/dpf-cleanup.sh cleanup-dpf

# Force finalize namespace
scripts/dpf-cleanup.sh force-cleanup-namespace

# Recreate namespace
scripts/dpf-cleanup.sh recreate-namespace
```

## Safety Features

- **Interactive Confirmation**: The main cleanup operation requires user confirmation
- **Graceful Degradation**: Operations continue even if some resources don't exist
- **Error Handling**: Uses `|| true` patterns to prevent script failure on missing resources
- **Logging**: Provides detailed progress information with emoji indicators

## When to Use

Use the DPF cleanup operations when:

- Switching between DPF versions
- Resolving deployment conflicts
- Starting fresh after failed installations
- Cleaning up test environments
- Troubleshooting stuck resources

## Environment Requirements

The cleanup scripts require:
- `oc` CLI configured and authenticated
- `helm` CLI (optional, for Helm release cleanup)
- `jq` for JSON processing (for namespace finalization)
- Proper KUBECONFIG environment or file

## Example Usage Workflow

```bash
# 1. Clean up existing DPF installation
make cleanup-dpf

# 2. Wait for confirmation that cleanup completed
# 3. Deploy fresh DPF installation
make deploy-dpf
```

This provides a clean slate for DPF deployments and eliminates the manual cleanup steps that were previously required. 