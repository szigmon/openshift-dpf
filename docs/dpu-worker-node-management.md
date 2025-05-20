# DPU Worker Node Management

This document provides instructions for managing worker nodes with BlueField DPUs in OpenShift clusters.

## Overview

Adding worker nodes with BlueField DPUs to your OpenShift cluster is a straightforward process. The key steps include creating a day2 cluster, obtaining the worker ISO, and booting your worker nodes with this ISO.

## Prerequisites

Before adding worker nodes with BlueField DPUs, ensure:

- The OpenShift cluster is installed and running
- The DPF operator is deployed on the cluster
- You have access to iDRAC or equivalent out-of-band management for the worker nodes

## Quick Start Guide

The fastest way to add BlueField DPU worker nodes is:

```bash
# Create day2 cluster and get worker ISO URL in one step (uses minimal ISO by default)
make create-cluster-iso

# Or if you need the full ISO instead
ISO_TYPE=full make create-cluster-iso
```

This single command creates a day2 cluster in Assisted Installer and provides the ISO URL for your worker nodes.

## Step-by-Step Process

If you prefer a step-by-step approach:

### 1. Create a Day2 Cluster

```bash
make create-day2-cluster
```

This creates a special cluster in Assisted Installer for adding worker nodes.

### 2. Get the Worker ISO URL

```bash
make get-worker-iso
```

You'll receive a URL that you can use to download the worker node ISO.

### 3. Deploy the Worker Node

1. Download the ISO from the URL provided
2. Use iDRAC Virtual Media to mount the ISO on your worker node
3. Boot the server from the ISO
4. The node will automatically register with the cluster

### 4. Verify Node Integration

```bash
oc get nodes
```

Look for your new worker node in the list and verify its status is Ready.

## Troubleshooting

### ISO URL Not Found

If you can't get the ISO URL:

```bash
# Try recreating the day2 cluster
make create-day2-cluster
make get-worker-iso
```

Or check the Assisted Installer UI directly at console.redhat.com.

### Worker Node Not Registering

If the worker node boots but doesn't register:

1. Verify network connectivity from the worker node to the internet
2. Ensure the ISO was downloaded completely and is not corrupted
3. Try downloading a fresh copy of the ISO and mounting it again

## Additional Information

The DPF automation handles most of the configuration automatically:

- The br-dpu bridge is configured by MachineConfig after the node joins
- The DPF operator detects the BlueField DPU and applies appropriate configurations
- No manual network configuration is required before booting the ISO

### ISO Type Options

The automation supports both minimal and full ISOs:

- **Minimal ISO (default)**: Smaller and faster to download, contains only essential packages
- **Full ISO**: Larger but includes more packages which might be needed in certain environments

You can select the ISO type using the `ISO_TYPE` environment variable:

```bash
# Use minimal ISO (default)
make create-cluster-iso

# Explicitly use minimal ISO
ISO_TYPE=minimal make create-cluster-iso

# Use full ISO instead
ISO_TYPE=full make create-cluster-iso
```

### Technical Details

- ISOs are properly resources of the infraenv, not the cluster directly
- Multiple fallback methods are used to retrieve the ISO URL if the primary method fails
- Version consistency is maintained between original and day2 clusters
- The ISO URL is automatically modified to use the requested ISO type (minimal or full)
- Color highlighting is used for better visibility of ISO URLs in the terminal output

## Advanced ISO Management

The automation provides a unified approach to ISO management:

```bash
# Get ISO URL for master nodes (default behavior)
make get-iso

# Download ISO for master nodes to local filesystem
make get-iso ACTION=download PATH=/path/to/save/iso

# Get ISO URL for worker nodes with BlueField DPUs
make get-iso NODE_TYPE=worker

# Download ISO for worker nodes to local filesystem (uncommon)
make get-iso NODE_TYPE=worker ACTION=download PATH=/path/to/save/iso

# Choose between minimal or full ISO (minimal is default)
make get-iso NODE_TYPE=worker ISO_TYPE=minimal
# or for full ISO
make get-iso NODE_TYPE=worker ISO_TYPE=full

# Or use with the create-cluster-iso target
ISO_TYPE=minimal make create-cluster-iso
# or
ISO_TYPE=full make create-cluster-iso
```

For convenience, you can also set the ISO URL manually if automatic retrieval fails:

```bash
ISO_URL="<your-iso-url>" make get-iso NODE_TYPE=worker
``` 