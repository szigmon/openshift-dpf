# Worker ISO Management for BlueField DPUs

This document provides detailed information on how to use the worker ISO management features for BlueField DPU nodes in the OpenShift DPF automation framework.

## Overview

The worker ISO management functionality allows you to:

1. Create day2 clusters for adding worker nodes with BlueField DPUs
2. Get download URLs for worker ISOs (both minimal and full versions)
3. Download worker ISO files to your system for offline DPU installation
4. Choose between minimal and full ISO types based on your requirements

## Prerequisites

- An existing OpenShift cluster created with the DPF automation
- Assisted Installer CLI (`aicli`) installed and configured
- Valid OpenShift authentication (offline token or active session)

## Workflow

The typical workflow for using worker ISOs with BlueField DPUs is:

1. Create a day2 cluster
2. Get the worker ISO URL or download the ISO file
3. Use the ISO to install worker nodes with BlueField DPUs
4. Join the worker nodes to your cluster

## Available Commands

### Creating a Day2 Cluster

A day2 cluster is required for worker node expansion. Create one with:

```bash
make create-day2-cluster
```

This creates a day2 cluster based on your existing cluster configuration, inheriting settings like base domain, pull secret, and networking configuration.

### Getting the Worker ISO URL

To get the direct download URL for a worker ISO:

```bash
# For minimal ISO (default)
make get-worker-iso

# For full ISO
make get-worker-iso ISO_TYPE=full
```

This command outputs the URL that can be used to download the ISO manually or provided to other systems.

### Downloading the Worker ISO File

To download the worker ISO directly to your system:

```bash
# Download minimal ISO to default location
make create-cluster-iso

# Download full ISO to default location
make create-cluster-iso ISO_TYPE=full

# Download ISO to custom location
make create-cluster-iso ISO_OUTPUT=/path/to/custom-worker.iso

# Non-interactive download (useful for scripts)
make create-cluster-iso NON_INTERACTIVE=true
```

## Configuration Options

The worker ISO functionality can be configured through the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `ISO_TYPE` | Type of ISO to download (`minimal` or `full`) | `minimal` |
| `ISO_FOLDER` | Default folder for ISO downloads | `/var/lib/libvirt/images` |
| `ISO_OUTPUT` | Custom output path for the ISO file | `${ISO_FOLDER}/worker-${CLUSTER_NAME}-${iso_type}.iso` |
| `NON_INTERACTIVE` | Skip user prompts (for automation) | `false` |

These variables can be set in your `.env` file or passed directly to the `make` command.

## ISO Types

### Minimal ISO

The minimal ISO (`minimal` or `minimal-iso`) is a smaller, streamlined image that:
- Is faster to download (typically 100-200MB)
- Contains just enough to bootstrap the node
- Downloads additional packages during installation

### Full ISO

The full ISO (`full` or `full-iso`) is a comprehensive image that:
- Is larger (typically 1-2GB)
- Contains all required packages
- Does not need to download additional packages during installation
- Is useful for air-gapped environments

## Authentication

The worker ISO download process requires authentication with the Red Hat API. The system will:

1. Try to use an existing aicli token
2. Fall back to using the offline token (if available)
3. Attempt to exchange the offline token for an access token
4. Try alternative authentication methods if needed

## Troubleshooting

### Common Issues

#### Failed to Get Worker ISO URL

If you see `No ISO URL found for <cluster-name>-day2`, try:
- Ensure your OpenShift offline token is valid
- Check that the day2 cluster was created successfully
- Verify your internet connection and API access

#### Download Fails

If the ISO download fails:
- Check your network connection
- Ensure you have sufficient disk space
- Try the full URL manually in a browser to verify access
- Look for API rate limiting or authentication issues

### Logs

The worker ISO functionality creates detailed logs during execution. Use these to diagnose issues:

```bash
# Enable debug logging
DEBUG=true make create-cluster-iso
```

## Advanced Usage

### Scripting and Automation

For use in scripts or CI/CD pipelines, use the non-interactive mode:

```bash
# Example script
#!/bin/bash
# Create day2 cluster and download both ISO types
make create-day2-cluster
make create-cluster-iso ISO_TYPE=minimal ISO_OUTPUT=/path/to/worker-minimal.iso NON_INTERACTIVE=true
make create-cluster-iso ISO_TYPE=full ISO_OUTPUT=/path/to/worker-full.iso NON_INTERACTIVE=true
```

### Testing

A test script is provided to validate the worker ISO functionality:

```bash
./test-worker-iso.sh
```

This script tests:
- Day2 cluster creation
- ISO URL retrieval for both minimal and full ISOs
- ISO download for both types
- Overwrite functionality
- Default and custom output locations 