# Frequently Asked Questions (FAQ)

---

**Q: What hardware is required for this automation?**
A: You need a supported hypervisor, OCP worker nodes, NVIDIA BlueField-3 DPUs, and a compatible switch (e.g., NVIDIA Cumulus 200GbE). See [prerequisites.md](prerequisites.md) for details.

**Q: Can I use this automation if I already have an OpenShift cluster?**
A: Yes! You can skip the cluster installation step and use the building blocks to install DPF, provision DPUs, and deploy DOCA services.

**Q: What if a script fails partway through?**
A: Most scripts are idempotent and can be safely re-run. Check the troubleshooting guide for specific errors.

**Q: Can I run only a specific step (e.g., just DPU provisioning)?**
A: Yes. Each major step (DPF install, DPU provisioning, DOCA deployment) can be run independently. See the relevant section in the docs.

**Q: How do I check if my DPUs are provisioned correctly?**
A: Use `oc get dpu -A` and `oc get nodes` to verify DPU status and node registration.

**Q: Where can I find more detailed documentation or support?**
A: See the [Resources](resources.md) section for links to official documentation and support. For advanced help, consult the official DOCA and DPF documentation.

**Q: What if I need to customize the manifests or automation?**
A: You can edit the generated manifests in the `generated/` directory or modify the scripts as needed. Review the README and comments in each script for guidance.

**Q: How do I report a bug or request a feature?**
A: Open an issue or pull request in the GitHub repository, or reach out via the project's support channels.

---

[Next: Resources](resources.md)

For more help, see the [Troubleshooting Guide](troubleshooting.md) or the [Full Installation Guide](full-installation.md).
