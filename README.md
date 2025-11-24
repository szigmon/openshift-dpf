# ⚠️ REPOSITORY ARCHIVED ⚠️

> **This repository has been archived and moved to a new location:**
>
> **🔗 New location: https://github.com/rh-ecosystem-edge/openshift-dpf**
>
> Please use the new repository for the latest updates, issues, and contributions.

---

# OpenShift DPF Deployment
Complete automation for deploying and managing NVIDIA DPF (Data Processing Framework) on OpenShift clusters.

## Project Structure
```
openshift-dpf/
├── Makefile                    # Main orchestration Makefile
├── .env                        # Environment variables configuration
├── manifests/                  # Manifests for all components
│   ├── cluster-installation/   # OpenShift/OVN cluster manifests
│   ├── dpf-installation/       # DPF operator manifests
│   ├── post-installation/      # Post-install configurations
│   └── worker-perfomance-configurations/ # Worker node performance tuning
├── scripts/                    # Automation scripts
│   ├── env.sh                  # Environment variable loading
│   ├── utils.sh                # Common utility functions
│   ├── cluster.sh              # Cluster management functions
│   ├── manifests.sh            # Manifest management functions
│   ├── tools.sh                # Tool installation functions
│   ├── dpf.sh                  # DPF deployment functions
│   └── vm.sh                   # VM management functions
├── configuration_templates/    # Templates for configuration
└── README.md                   # Main project documentation
```

## Prerequisites
- OpenShift CLI (`oc`)
- Assisted Installer CLI ([`aicli`](https://aicli.readthedocs.io))
- Helm
- Go (for NFD operator deployment)
- jq (for JSON processing)
- Access to Red Hat Console
- NVIDIA DPU hardware
- Required pull secrets:
  - OpenShift pull secret (`openshift_pull.json`)
  - DPF pull secret (`pull-secret.txt`)
    - https://catalog.ngc.nvidia.com -> Setup -> Generate API Key
    - `echo "$oauthtoken:<nvapi-key>" | base64`
    - write following format to pull-secret.txt:
      `{"auths":{"nvcr.io":{"username":"$oauthtoken","password":"<nvapi-key>","auth":"<base64 of ($oauthtoken:<nvapi-key>)>"}`
- Openshift offline token
  - Create token via https://cloud.redhat.com/openshift/token
  - Write token to ~/.aicli/offlinetoken.txt
  - Verify with `aicli list clusters`

## Features
This automation provides:

### Cluster Installation
- OpenShift cluster creation with assisted installer
- Support for single node or multi-node clusters
- OVN networking with NVIDIA configuration
- OpenShift cert-manager deployment
- Support for VM creation and management

### DPF Installation
- DPF operator deployment
- SR-IOV operator configuration
- Node Feature Discovery (NFD) support
- Component configuration and validation

### Cluster Management Options
- Kamaji-based DPU cluster (default)
- Hypershift-based DPU cluster (optional)

## Getting Started

1. Clone the repository:
```bash
git clone https://github.com/yourusername/openshift-dpf.git
cd openshift-dpf
```

2. Configure your environment:
   - Copy the example environment file: `cp .env.example .env`
   - Edit `.env` to set your desired configuration values
   - Place your OpenShift pull secret in `openshift_pull.json`
   - Place your DPF pull secret in `pull-secret.txt`

3. Run complete installation:
```bash
make all
```

## Configuration Options

### Environment Variables
All configuration options are now managed through the `.env` file. This provides a centralized, consistent way to configure the deployment.

The `.env` file contains sections for:
- Cluster Configuration
- Directory Structure
- Helm Configuration
- NFD Configuration
- Hypershift Configuration
- Network Configuration
- VM Configuration
- And more...

To customize your deployment, simply edit the values in the `.env` file.

### Basic Configuration
```bash
# Edit .env file to set these values
CLUSTER_NAME=my-cluster
BASE_DOMAIN=my.domain
OPENSHIFT_VERSION=4.18.4
```

Default values:
- CLUSTER_NAME: doca-cluster
- BASE_DOMAIN: okoyl.xyz
- OPENSHIFT_VERSION: 4.19.0-ec.3

### Switching Between Kamaji and Hypershift

By default, the automation uses Kamaji as the cluster manager. To use Hypershift instead:

```bash
# Edit .env file to set
DPF_CLUSTER_TYPE=hypershift
```

To explicitly specify Kamaji (default behavior):

```bash
# Edit .env file to set
DPF_CLUSTER_TYPE=kamaji
```

### NFD Deployment

To deploy Node Feature Discovery separately:

```bash
make deploy-nfd
```

## Advanced Usage

The automation includes many additional targets for fine-grained control:

```bash
# View all available targets and configuration options
make help

# Create just the OpenShift cluster without DPF
make create-cluster cluster-install

# Deploy only DPF components on an existing cluster
make deploy-dpf

# Install Hypershift operator and create a hosted cluster
make install-hypershift create-hypershift-cluster

# Clean up resources
make clean-all
```

## Contributing
1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License
This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## Support
For issues and feature requests, please open an issue in the GitHub repository.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/szigmon/openshift-dpf)
