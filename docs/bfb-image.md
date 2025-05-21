# Building a BFB Image

## What is a BFB Image?
A BFB (BlueField Bootable Flash) image is required to provision NVIDIA BlueField DPUs. It contains the firmware, OS, and configuration needed for the DPU to operate in your environment.

## How to Obtain or Build a BFB Image

### 1. Download an Official BFB Image
- Visit the [NVIDIA DOCA Portal](https://docs.nvidia.com/doca/) or your enterprise repository.
- Download the appropriate BFB image for your BlueField DPU model and desired DOCA version.

### 2. (Optional) Build a Custom BFB Image
- Use NVIDIA's bf-builder or similar tools to customize your BFB image.
- Example:
  ```bash
  bf-builder --input <config.yaml> --output <custom.bfb>
  ```
- See the [NVIDIA DOCA documentation](https://docs.nvidia.com/doca/) for advanced options.

### 3. Verify the BFB Image
```bash
file <your-image.bfb>
```
- The output should indicate a valid BFB image file.

> **Tip:** Store your BFB images in a secure, backed-up location for future use.

---

[Next: DPU Provisioning](dpu-provisioning.md) 