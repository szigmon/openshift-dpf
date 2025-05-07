# Prerequisites

Before you begin, ensure you have the following:

## Hardware
- At least one hypervisor node (for control plane VMs)
- At least two worker nodes with NVIDIA BlueField-3 (BF3) DPUs
- Management switch (1GbE) and NVIDIA Cumulus 200GbE switch
- See architecture diagram in the main README or blog

## Software
- OpenShift Container Platform (OCP) 4.12 or newer
- Access to Red Hat and NVIDIA container registries
- `oc` CLI, `kubectl`, `hypershift` CLI
- Python 3.x (for some scripts)
- Git

## Network
- Management network (1GbE) for all nodes
- Data network (2x 200GbE) for each DPU
- Proper VLANs and IP addressing for all nodes and DPUs

## Credentials
- OpenShift pull secret
- DPF pull secret (if required)
- SSH key for cluster access
- Sudo/root access on all nodes

## Other
- Sufficient disk space on all nodes
- Internet access for pulling images and dependencies

---

**Tip:** For a full bill of materials and validated hardware, see the [NVIDIA DPF on OpenShift Blog](https://developers.redhat.com/articles/2025/03/20/dpu-enabled-networking-openshift-and-nvidia-dpf).
