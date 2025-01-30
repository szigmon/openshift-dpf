# OpenShift DPF Deployment

Complete automation for deploying and managing NVIDIA DPF (Data Processing Framework) on OpenShift clusters.

> **Note:** This project is under active development. Currently, only the pre-installation module is implemented and working. DPF installation and provisioning modules are in progress.

## Project Structure

```
openshift-dpf/
├── Makefile                    # Main orchestration Makefile
├── pre-installation/          # Pre-installation configuration (Implemented)
│   ├── Makefile              # Pre-installation automation
│   ├── manifests/            # OpenShift manifests
│   │   ├── ovn-values.yaml   # OVN configuration
│   │   └── *.yaml           # Other required manifests
│   └── README.md             # Pre-installation documentation
├── dpf-installation/         # DPF operator installation (In Progress)
├── dpf-provisioning/         # DPF provisioning and configuration (In Progress)
└── README.md                 # Main project documentation
```

## Prerequisites

- OpenShift CLI (`oc`)
- Assisted Installer CLI (`aicli`)
- Helm
- Access to Red Hat Console
- NVIDIA DPU hardware
- Required pull secrets:
  - OpenShift pull secret (`openshift_pull.json`)
  - DPF pull secret (`pull-secret.txt`)

## Current Functionality

### Pre-Installation (Implemented)
The pre-installation module automates:
- OpenShift cluster creation with assisted installer
- OVN network configuration
- Required manifest generation and application

To use the pre-installation module:
```bash
# Run pre-installation
make pre-install

# Clean up pre-installation
make clean-pre-install
```

### Upcoming Features (In Progress)
1. DPF Installation Module
   - Operator deployment
   - Component configuration
   - Validation checks

2. DPF Provisioning Module
   - DPU configuration
   - Network setup
   - Validation and testing

## Getting Started

1. Clone the repository:
```bash
git clone https://github.com/yourusername/openshift-dpf.git
cd openshift-dpf
```

2. Configure your environment:
   - Place your OpenShift pull secret in `openshift_pull.json`
   - Place your DPF pull secret in `pull-secret.txt`

3. Run pre-installation:
```bash
make pre-install
```

## Configuration

Pre-installation configuration options:
```bash
make pre-install CLUSTER_NAME=my-cluster BASE_DOMAIN=my.domain OPENSHIFT_VERSION=4.17.12
```

Default values:
- CLUSTER_NAME: doca-cluster
- BASE_DOMAIN: karmalabs.corp
- OPENSHIFT_VERSION: 4.17.12

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