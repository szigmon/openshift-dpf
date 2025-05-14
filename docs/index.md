# NVIDIA DPF on OpenShift: Integration Guide

Welcome to the official documentation for deploying the **NVIDIA DOCA Platform Framework (DPF) Operator** on Red Hat OpenShift. This guide is for technical users—platform engineers, DevOps teams, and solution architects—who want to:

- Deploy and operate the DPF Operator on OpenShift
- Use DPF to provision and manage the lifecycle of NVIDIA BlueField DPUs
- Deploy and manage DOCA services on top of provisioned DPUs

**Note:** While DOCA services are a key use case, the primary focus is DPF on OpenShift. DOCA is deployed and managed as a layer on top of DPF-managed DPUs.

---

## Quickstart

For those who want to get started immediately:

1. [Prerequisites](prerequisites.md) - Ensure your environment meets all requirements
2. [Install OpenShift](cluster-creation.md) - Deploy a new OpenShift cluster
3. [Install DPF Operator](dpf-operator.md) - Deploy the NVIDIA DPF Operator
4. [Provision DPUs](dpu-provisioning.md) - Configure and provision BlueField DPUs
5. [Deploy DOCA Services](doca-services.md) - Deploy accelerated networking services
6. [Troubleshooting](troubleshooting.md) - Resolve common issues

---

## Why Use This Guide?
- **Accelerate and simplify DPF deployment:**
    - Proven, automated workflows for deploying the DPF Operator on OpenShift
    - Minimize manual steps and reduce errors
- **End-to-end DPU lifecycle management:**
    - Provision, configure, and manage BlueField DPUs using DPF
    - Automate upgrades, scaling, and monitoring
- **Deploy DOCA services on top:**
    - Use DPF-managed DPUs as the foundation for DOCA workloads
    - Step-by-step guidance for deploying and validating DOCA services
- **Enterprise-grade documentation:**
    - Modular, scenario-based structure
    - Step-by-step guides with validation and troubleshooting
    - Architecture diagrams and workflow charts
    - Consistent, user-centric navigation

---

## What You'll Find Here
- **Introduction & Architecture**  
  Overview, benefits, and architecture diagrams
- **Prerequisites & Planning**  
  Hardware/software requirements, network and security planning, decision trees
- **Installation Guides**  
  Complete deployment, existing cluster, and service-focused configuration guides
- **Operations & Management**  
  Monitoring, scaling, upgrades, and troubleshooting
- **Use Cases & Examples**  
  Real-world scenarios, performance benchmarks, advanced configurations
- **Reference**  
  CLI/API documentation, configuration parameters, resource requirements
- **FAQ & Resources**  
  Common questions and links to official support

---

## Getting Started
- **New to DPF on OpenShift?** Start with [Introduction](introduction.md)
- **Ready to plan your deployment?** See [Prerequisites](prerequisites.md)
- **Know your scenario?** Jump to [Complete Deployment](full-installation.md) for step-by-step guides

For advanced topics, troubleshooting, and reference, use the navigation menu or search.

---

## Demo Video

Watch our comprehensive demo of the NVIDIA DPF OpenShift integration:

<div style="padding:56.25% 0 0 0;position:relative;"><iframe src="https://player.vimeo.com/video/1064347217?h=471702be0b&amp;badge=0&amp;autopause=0&amp;player_id=0&amp;app_id=58479" frameborder="0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen style="position:absolute;top:0;left:0;width:100%;height:100%;" title="NVIDIA DPF on OpenShift Demo"></iframe></div>

---

## Resources

### Documentation
- [NVIDIA DPF Documentation](https://docs.nvidia.com/networking/display/dpftest1/dpf+user+guides) - Official NVIDIA DPF product documentation
- [Red Hat OpenShift Documentation](https://docs.openshift.com/container-platform/latest/welcome/index.html) - Official OpenShift platform documentation
- [NVIDIA BlueField DPU Documentation](https://developer.nvidia.com/networking/dpu) - BlueField DPU technical resources

### GitHub Repositories
- [OpenShift-DPF Automation Repository](https://github.com/szigmon/openshift-dpf) - This automation tooling repository
- [NVIDIA DOCA Platform Framework](https://github.com/NVIDIA/doca-platform) - DPF operator source code

### Reference Deployments & Blogs
- [DPF with OVN-Kubernetes and HBN Services (RDG)](https://docs.nvidia.com/networking/display/public/sol/rdg+for+dpf+with+ovn-kubernetes+and+hbn+services) - NVIDIA Reference Deployment Guide
- [DPU-Enabled Networking on OpenShift with NVIDIA DPF](https://developers.redhat.com/articles/2025/03/20/dpu-enabled-networking-openshift-and-nvidia-dpf) - Red Hat Developer article
- [NVIDIA DOCA Framework](https://developer.nvidia.com/networking/doca) - NVIDIA DOCA information and resources

For support, see the [FAQ](faq.md) or [Resources](resources.md) sections.
