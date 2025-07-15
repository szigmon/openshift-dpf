#!/bin/bash
# vm.sh - Virtual Machine Management

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"



# Configuration with defaults
VM_PREFIX=${VM_PREFIX:-"vm-dpf"}
VM_COUNT=${VM_COUNT:-3}

# Get the default physical NIC
PHYSICAL_NIC=${PHYSICAL_NIC:-$(ip route | awk '/default/ {print $5; exit}')}
API_VIP=${API_VIP}
BRIDGE_NAME=${BRIDGE_NAME:-br0}
RAM=${RAM:-16384}  # Memory in MB
VCPUS=${VCPUS:-8}   # Number of virtual CPUs
DISK_SIZE1=${DISK_SIZE1:-120}  # Size of first disk
DISK_SIZE2=${DISK_SIZE2:-40}  # Size of second disk
DISK_PATH=${DISK_PATH:-"/var/lib/libvirt/images"}
ISO_PATH="${ISO_FOLDER}/${CLUSTER_NAME}.iso"


# -----------------------------------------------------------------------------
# VM Management Functions
# -----------------------------------------------------------------------------
# * Create VMs with prefix $VM_PREFIX.
# *
# * This function creates $VM_COUNT number of VMs with the given prefix.
# * The VMs are created with the given memory, number of virtual CPUs,
# * and disk sizes. The VMs are also configured with a direct network
# * connection to the given physical NIC and a VNC graphics device.
# * The function waits for all VMs to be running using a retry mechanism
# * and prints a success message upon completion.

function create_vms() {
    # First check if cluster is already installed
    if check_cluster_installed; then
        log "INFO" "Skipping VM creation as cluster is already installed"
        return 0
    fi
    
    log "Creating VMs with prefix $VM_PREFIX..."

    if [ "$SKIP_BRIDGE_CONFIG" != "true" ]; then
        # Ensure the bridge is created before creating VMs
        echo "Creating bridge with force mode..."
        "$(dirname "${BASH_SOURCE[0]}")/vm-bridge-ops.sh" --force
    else
        echo "Skipping bridge creation as SKIP_BRIDGE_CONFIG is set to true."
    fi

    # --- MAC Address Generation Functions ---
    
    # Function to generate a unique MAC address based on machine-id and VM name
    generate_mac_from_machine_id() {
        local vm_name="$1"
        
        # Get machine-id from /etc/machine-id
        if [ ! -f "/etc/machine-id" ]; then
            log "ERROR" "Could not find /etc/machine-id file."
            exit 1
        fi
        
        local machine_id=$(cat /etc/machine-id)
        local combined="${machine_id}-${vm_name}"
        local hash=$(echo "$combined" | sha256sum | cut -c1-10)
        
        # Use QEMU's standard locally administered MAC prefix (52:54:00)
        local mac="52:54:00:$(echo "$hash" | sed 's/\(..\)\(..\)\(..\).*/\1:\2:\3/')"
        
        echo "$mac"
    }

    # Function to generate MAC address with custom prefix
    generate_mac_with_custom_prefix() {
        local vm_index="$1"
        local custom_prefix="$2"
        
        # Validate custom prefix format (must be 4 hex digits with colon)
        if [[ ! "$custom_prefix" =~ ^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$ ]]; then
            log "ERROR" "Invalid MAC_PREFIX format: $custom_prefix. Must be 4 hex digits with colon (e.g., 'C0:00', 'A1:B2')"
            exit 1
        fi
        
        # Convert VM index to hex (01, 02, 03, etc.)
        local last_octet_hex=$(printf '%02x' "$vm_index")
        
        # Format: "C0:00" -> use as is
        local mac="52:54:00:${custom_prefix}:${last_octet_hex}"
        
        echo "$mac"
    }

    # --- VM Creation Loop ---
    for i in $(seq 1 "$VM_COUNT"); do
        VM_NAME="${VM_PREFIX}${i}"
        network_mac_arg=""

        # Determine MAC assignment method based on MAC_PREFIX
        if [ -n "$MAC_PREFIX" ]; then
            # Use custom prefix if MAC_PREFIX is specified
            UNIQUE_MAC=$(generate_mac_with_custom_prefix "$i" "$MAC_PREFIX")
            log "INFO" "Creating VM: $VM_NAME with custom prefix MAC: $UNIQUE_MAC"
            network_mac_arg=",mac=${UNIQUE_MAC}"
        else
            # Use machine-id based MAC (default)
            UNIQUE_MAC=$(generate_mac_from_machine_id "$VM_NAME")
            log "INFO" "Creating VM: $VM_NAME with machine-id based MAC: $UNIQUE_MAC"
            network_mac_arg=",mac=${UNIQUE_MAC}"
        fi

        # Construct the full --network argument string
        network_full_arg="bridge=${BRIDGE_NAME},model=e1000e${network_mac_arg}"

        # Create VM with virt-install
        log "INFO" "Starting VM creation for $VM_NAME..."
        nohup virt-install --name "$VM_NAME" --memory "$RAM" \
                --vcpus "$VCPUS" \
                --os-variant=rhel9.4 \
                --disk pool=default,size="${DISK_SIZE1}" \
                --disk pool=default,size="${DISK_SIZE2}" \
                --network "${network_full_arg}" \
                --graphics=vnc \
                --events on_reboot=restart \
                --cdrom "$ISO_PATH" \
                --cpu host-passthrough \
                --noautoconsole \
                --wait=-1 &
    done

    # Wait for all VMs to be running using retry mechanism
    MAX_RETRIES=24  # 2 minutes (24 retries * 5s)
    INTERVAL=5      # Check every 5 seconds

    for i in $(seq 1 "$VM_COUNT"); do
        VM_NAME="${VM_PREFIX}${i}"
        retries=0
        until [[ "$(virsh domstate "$VM_NAME" 2>/dev/null || true )" == "running" ]]; do
            if [[ $retries -ge $MAX_RETRIES ]]; then
                echo "Error: VM $VM_NAME did not reach running state within 2 minutes."
                exit 1
            fi
            echo "Waiting for VM $VM_NAME to start... (Attempt: $((retries + 1))/$MAX_RETRIES)"
            sleep $INTERVAL
            ((retries+=1))
        done
        echo "VM $VM_NAME is running."
    done
    log "VM creation completed successfully!"
}

function delete_vms() {
    local prefix=${VM_PREFIX}
    log "INFO" "Deleting VMs with prefix ${prefix}..."
    local vms=$(virsh list --all | grep ${prefix} | awk '{print $2}')
    for vm in ${vms}; do
        if ! virsh destroy ${vm} 2>/dev/null; then
            log "WARNING" "Failed to destroy VM ${vm}, continuing anyway"
        fi
        if ! virsh undefine ${vm} --remove-all-storage 2>/dev/null; then
            log "WARNING" "Failed to undefine VM ${vm}, continuing anyway"
        fi
    done
    log "INFO" "VMs with prefix ${prefix} deleted successfully"
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    case "$command" in
        create)
            create_vms
            ;;
        delete)
            delete_vms
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: create, delete"
            exit 1
            ;;
    esac
}

# If script is executed directly (not sourced), run the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log "Usage: $0 <command> [arguments...]"
        log "Commands:"
        log "  create - Create VMs for the cluster"
        log "  delete - Delete VMs with the specified prefix"
        exit 1
    fi
    
    main "$@"
fi
