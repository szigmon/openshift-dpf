# NVIDIA DPF Deployment for OpenShift
Complete automation for deploying and managing NVIDIA DPF (Data Processing Framework) on OpenShift clusters. This project provides end-to-end automation for pre-installation configuration, DPF installation, and DPF provisioning.

## Project Structure

```
openshift-dpf/
├── Makefile                    # Main orchestration Makefile
├── pre-installation/          # Pre-installation configuration
│   ├── Makefile              # Pre-installation automation
│   ├── manifests/            # OpenShift manifests
│   │   ├── ovn-values.yaml   # OVN configuration
│   │   └── *.yaml           # Other required manifests
│   └── README.md             # Pre-installation documentation
├── dpf-installation/         # DPF operator installation
│   ├── Makefile              # Installation automation
│   ├── manifests/            # DPF operator manifests
│   └── README.md             # Installation documentation
├── dpf-provisioning/         # DPF provisioning and configuration
│   ├── Makefile              # Provisioning automation
│   ├── configs/              # Provisioning configurations
│   └── README.md             # Provisioning documentation
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

## Getting Started

1. Clone the repository:
```bash
git clone https://github.com/yourusername/openshift-dpf.git
cd openshift-dpf
```

2. Configure your environment:
   - Place your OpenShift pull secret in `openshift_pull.json`
   - Place your DPF pull secret in `pull-secret.txt`

3. Run the complete deployment:
```bash
make all
```

## Deployment Stages

### 1. Pre-Installation
Configures the OpenShift cluster with required networking components:
```bash
make pre-install
```

### 2. DPF Installation
Installs the DPF operator and required components:
```bash
make install-dpf
```

### 3. DPF Provisioning
Configures and provisions DPF components:
```bash
make provision-dpf
```

## Configuration

Each stage has its own configuration options. See the respective README files in each directory for detailed configuration options:

- [Pre-Installation Configuration](pre-installation/README.md)
- [DPF Installation Configuration](dpf-installation/README.md)
- [DPF Provisioning Configuration](dpf-provisioning/README.md)

## Usage Examples

1. Complete deployment with default settings:
```bash
make all
```

2. Run specific stages:
```bash
# Pre-installation only
make pre-install

# DPF installation only
make install-dpf

# DPF provisioning only
make provision-dpf
```

3. Clean up:
```bash
# Clean everything
make clean

# Clean specific stage
make clean-pre-install
make clean-dpf-install
make clean-dpf-provision
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