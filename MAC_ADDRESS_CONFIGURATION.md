# MAC Address Configuration for VM Creation

This document explains the MAC address assignment options available when creating VMs with the `vm.sh` script.

## Configuration Options

The script supports two MAC address assignment methods controlled by the `MAC_PREFIX` environment variable:

### 1. Machine-ID Based MAC Generation (Default)
```bash
# Leave MAC_PREFIX unset or set to empty
export MAC_PREFIX=""
```

**Behavior**: 
- Generates deterministic MAC addresses based on the host's machine-id and VM name
- Uses QEMU's standard locally administered MAC prefix: `52:54:00`
- Ensures consistent MAC addresses across VM recreations on the same host
- Format: `52:54:00:XX:XX:XX` where XX are derived from machine-id hash

**Requirements**: 
- Host must have `/etc/machine-id` file

### 2. Custom Prefix MAC Generation
```bash
export MAC_PREFIX="C0:00"  # 2-digit hex value or 4-digit with colon
```

**Behavior**:
- Generates MAC addresses with a custom prefix
- Format: `52:54:00:XX:YY:ZZ` where XX:YY is your custom prefix and ZZ is the VM index
- Examples:
  - With `MAC_PREFIX="C0:00"`:
    - vm-dpf1: `52:54:00:C0:00:01`
    - vm-dpf2: `52:54:00:C0:00:02`
  - With `MAC_PREFIX="A1:B2"`:
    - vm-dpf1: `52:54:00:A1:B2:01`
    - vm-dpf2: `52:54:00:A1:B2:02`

**Requirements**:
- `MAC_PREFIX` must be set to a 4-digit hexadecimal value with colon (e.g., "C0:00", "A1:B2", "FF:EE")

## Usage Examples

### Example 1: Use machine-id based MAC addresses (default)
```bash
# No environment variables needed (default behavior)
./scripts/vm.sh create
```

### Example 2: Use custom prefix MAC addresses
```bash
export MAC_PREFIX="C0:00"
./scripts/vm.sh create
```

### Example 3: Using .env file
Add to your `.env` file:
```bash
MAC_PREFIX=C0:00
```

## Validation

The script includes validation for:
- Custom prefix format (4-digit hex with colon)
- Machine-id file existence

## Error Handling

The script will exit with an error if:
- Invalid `MAC_PREFIX` format is specified
- `/etc/machine-id` file is not found when using default method

## Notes

- All generated MAC addresses use the locally administered address space (52:54:00 prefix)
- Machine-id based MACs are deterministic and will be the same for the same VM name on the same host
- Custom prefix MACs are predictable and follow a simple numbering scheme
- The script maintains backward compatibility - existing deployments will continue to work unchanged 