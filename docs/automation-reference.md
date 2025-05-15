# Automation Reference

This section is under construction.

## Makefile Targets

| Target                | Description                                                      |
|----------------------|------------------------------------------------------------------|
| `make all`           | Runs the full end-to-end flow: cluster, DPF, DPU, DOCA, etc.      |
| `make clean-all`     | Cleans up all generated files and resources                       |
| `make prepare-dpf-manifests` | Generates manifests for your environment                  |
| `make apply-dpf`     | Installs DPF operator and dependencies                            |
| `make provision-dpu` | Provisions DPUs                                                   |
| `make deploy-doca`   | Deploys DOCA services                                             |
| `make run-benchmark` | Runs benchmarks (if available)                                    |

> **Tip:** Run `make help` to see all available targets and their descriptions.

## Script Reference

| Script                          | Description                                 |
|---------------------------------|---------------------------------------------|
| `scripts/env.sh`                | Environment variables                       |
| `scripts/dpf.sh`                | Main automation entry point                 |
| `scripts/prepare-dpf-manifests.sh` | Manifest generation                      |
| `scripts/provision-dpu.sh`      | DPU provisioning                           |
| `scripts/deploy-doca.sh`        | DOCA deployment                            |
| `scripts/benchmark.sh`          | Benchmarking (if available)                |

---

[Next: Resources](resources.md) 