# MAC Address Configuration for VM Creation

This document explains the MAC address assignment options available when creating VMs with the `vm.sh` script.

## Configuration Options

The script supports three MAC address assignment methods controlled by the `MAC_ASSIGNMENT_METHOD` environment variable:

### 1. No Static MAC Assignment (Default)
```bash
export MAC_ASSIGNMENT_METHOD="none"
# or leave unset (default behavior)
```

**Behavior**: VMs are created with randomly generated MAC addresses by libvirt.

### 2. Machine-ID Based MAC Generation
```bash
export MAC_ASSIGNMENT_METHOD="machine-id"
```

**Behavior**: 
- Generates deterministic MAC addresses based on the host's machine-id and VM name
- Uses QEMU's standard locally administered MAC prefix: `52:54:00`
- Ensures consistent MAC addresses across VM recreations on the same host
- Format: `52:54:00:XX:XX:XX` where XX are derived from machine-id hash

**Requirements**: 
- Host must have `/etc/machine-id` or `/var/lib/dbus/machine-id` file

### 3. Custom Prefix MAC Generation
```bash
export MAC_ASSIGNMENT_METHOD="custom-prefix"
export MAC_CUSTOM_PREFIX="C0:00"  # 2-digit hex value or 4-digit with colon
```

**Behavior**:
- Generates MAC addresses with a custom prefix
- Supports two formats:
  - 2-digit format: `52:54:00:XX:00:YY` where XX is your custom prefix and YY is the VM index
  - 4-digit format: `52:54:00:XX:YY:ZZ` where XX:YY is your custom prefix and ZZ is the VM index
- Examples:
  - With `MAC_CUSTOM_PREFIX="01"`:
    - vm-dpf1: `52:54:00:01:00:01`
    - vm-dpf2: `52:54:00:01:00:02`
  - With `MAC_CUSTOM_PREFIX="C0:00"`:
    - vm-dpf1: `52:54:00:C0:00:01`
    - vm-dpf2: `52:54:00:C0:00:02`

**Requirements**:
- `MAC_CUSTOM_PREFIX` must be set to either:
  - 2-digit hexadecimal value (e.g., "01", "A1", "FF")
  - 4-digit hexadecimal value with colon (e.g., "C0:00", "A1:B2")

## Usage Examples

### Example 1: Use default random MAC addresses
```bash
# No environment variables needed (default behavior)
./scripts/vm.sh create
```

### Example 2: Use machine-id based MAC addresses
```bash
export MAC_ASSIGNMENT_METHOD="machine-id"
./scripts/vm.sh create
```

### Example 3: Use custom prefix MAC addresses
```bash
export MAC_ASSIGNMENT_METHOD="custom-prefix"
export MAC_CUSTOM_PREFIX="C0:00"
./scripts/vm.sh create
```

### Example 4: Using .env file
Add to your `.env` file:
```bash
MAC_ASSIGNMENT_METHOD=custom-prefix
MAC_CUSTOM_PREFIX=C0:00
```

## Validation

The script includes validation for:
- MAC address format (proper hex format with colons)
- Custom prefix format (2-digit hex or 4-digit hex with colon)
- Machine-id file existence
- Valid assignment method values

## Error Handling

The script will exit with an error if:
- Invalid `MAC_ASSIGNMENT_METHOD` is specified
- `MAC_CUSTOM_PREFIX` is missing when using "custom-prefix" method
- Machine-id file is not found when using "machine-id" method
- Generated MAC address is invalid

## Notes

- All generated MAC addresses use the locally administered address space (52:54:00 prefix)
- Machine-id based MACs are deterministic and will be the same for the same VM name on the same host
- Custom prefix MACs are predictable and follow a simple numbering scheme
- The script maintains backward compatibility - existing deployments will continue to work unchanged 