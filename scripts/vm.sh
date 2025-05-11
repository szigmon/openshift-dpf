#!/bin/bash
# vm.sh - Virtual Machine Management

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"



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
    log "Creating VMs with prefix $VM_PREFIX..."

    if [ "$SKIP_BRIDGE_CONFIG" != "true" ]; then
        # Ensure the bridge is created before creating VMs
        echo "Creating bridge with force mode..."
        "$(dirname "${BASH_SOURCE[0]}")/vm-bridge-ops.sh" --force
    else
        echo "Skipping bridge creation as SKIP_BRIDGE_CONFIG is set to true."
    fi

    # Create VMs
    for i in $(seq 1 "$VM_COUNT"); do
        VM_NAME="${VM_PREFIX}${i}"
        echo "Creating VM: $VM_NAME"
        nohup virt-install --name "$VM_NAME" --memory $RAM \
                --vcpus "$VCPUS" \
                --os-variant=rhel9.4 \
                --disk pool=default,size="${DISK_SIZE1}" \
                --disk pool=default,size="${DISK_SIZE2}" \
                --network bridge=${BRIDGE_NAME},mac="52:54:00:12:34:5${i}",model=e1000e \
                --network network=default \
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
