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
# RAM, VCPUS, DISK_SIZE1, DISK_SIZE2 are defined in env.sh
DISK_PATH=${DISK_PATH:-"/var/lib/libvirt/images"}
ISO_PATH="${ISO_FOLDER}/${CLUSTER_NAME}.iso"


# -----------------------------------------------------------------------------
# VM Management Functions
# -----------------------------------------------------------------------------
# * Create VMs with prefix $VM_PREFIX.
# *
# * This function creates $VM_COUNT number of VMs with the given prefix.
# * The VMs are created with the given memory (RAM from env.sh), 
# * number of virtual CPUs (VCPUS from env.sh), and disk sizes 
# * (DISK_SIZE1, DISK_SIZE2 from env.sh). The VMs are also configured 
# * with a direct network connection to the given physical NIC and a VNC 
# * graphics device. The function waits for all VMs to be running using 
# * a retry mechanism and prints a success message upon completion.

function create_vms() {
    # First check if cluster is already installed
    if check_cluster_installed; then
        log "INFO" "Skipping VM creation as cluster is already installed"
        return 0
    fi
    
    log "Creating VMs with prefix $VM_PREFIX..."

    # Check if ISO exists
    if [ ! -f "$ISO_PATH" ]; then
        log "ERROR" "ISO not found at $ISO_PATH. Please run 'make create-aicli-iso' first."
        return 1
    fi

    # Create disks and VMs
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-${i}"
        local disk1="${DISK_PATH}/${vm_name}-disk1.qcow2"
        local disk2="${DISK_PATH}/${vm_name}-disk2.qcow2"

        # Skip if VM already exists
        if virsh list --all | grep -q "$vm_name"; then
            log "VM $vm_name already exists. Skipping creation."
            continue
        fi

        # Create disk images
        log "Creating disks for $vm_name..."
        qemu-img create -f qcow2 "$disk1" "${DISK_SIZE1}G"
        qemu-img create -f qcow2 "$disk2" "${DISK_SIZE2}G"

        # Create VM
        log "Creating VM $vm_name..."
        virt-install \
            --name="$vm_name" \
            --memory="$RAM" \
            --vcpus="$VCPUS" \
            --disk "path=$disk1,size=$DISK_SIZE1,format=qcow2" \
            --disk "path=$disk2,size=$DISK_SIZE2,format=qcow2" \
            --network network=default,model=virtio \
            --network bridge=${BRIDGE_NAME},model=virtio \
            --os-variant=rhel9.0 \
            --cdrom="$ISO_PATH" \
            --graphics vnc \
            --noautoconsole \
            --boot hd,cdrom

        log "VM $vm_name created successfully."
    done

    # Start all VMs
    log "Starting all VMs..."
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-${i}"
        if ! virsh list --state-running | grep -q "$vm_name"; then
            virsh start "$vm_name" || log "WARN" "Failed to start $vm_name"
        fi
    done

    # Wait for VMs to be running
    log "Waiting for all VMs to be running..."
    local success=false
    for attempt in $(seq 1 30); do
        local all_running=true
        for i in $(seq 1 $VM_COUNT); do
            local vm_name="${VM_PREFIX}-${i}"
            if ! virsh list --state-running | grep -q "$vm_name"; then
                all_running=false
                break
            fi
        done
        
        if $all_running; then
            success=true
            break
        fi
        
        log "Attempt $attempt/30: Waiting for VMs to start..."
        sleep 10
    done

    if $success; then
        log "All VMs are running successfully!"
        list_vms
    else
        log "ERROR" "Timeout waiting for VMs to start"
        return 1
    fi
}

function destroy_vms() {
    log "Destroying VMs with prefix $VM_PREFIX..."
    
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-${i}"
        
        if virsh list --all | grep -q "$vm_name"; then
            log "Destroying VM $vm_name..."
            
            # Force stop if running
            if virsh list --state-running | grep -q "$vm_name"; then
                virsh destroy "$vm_name" || true
            fi
            
            # Undefine the VM
            virsh undefine "$vm_name" --remove-all-storage || true
            
            # Remove disk images manually if they still exist
            rm -f "${DISK_PATH}/${vm_name}-disk1.qcow2"
            rm -f "${DISK_PATH}/${vm_name}-disk2.qcow2"
            
            log "VM $vm_name destroyed."
        else
            log "VM $vm_name not found. Skipping."
        fi
    done
    
    log "All VMs destroyed."
}

function list_vms() {
    log "Listing VMs with prefix $VM_PREFIX..."
    virsh list --all | grep "$VM_PREFIX" || log "No VMs found with prefix $VM_PREFIX"
}

function update_api_vip() {
    local api_vip="$1"
    if [ -z "$api_vip" ]; then
        log "ERROR" "API VIP not provided"
        return 1
    fi
    
    log "Updating API VIP to $api_vip..."
    export API_VIP="$api_vip"
    
    # Update environment file if it exists
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/env.sh" ]; then
        sed -i.bak "s/^API_VIP=.*/API_VIP=\"$api_vip\"/" "$(dirname "${BASH_SOURCE[0]}")/env.sh"
        log "Updated API_VIP in env.sh"
    fi
}

# -----------------------------------------------------------------------------
# Main command handler
# -----------------------------------------------------------------------------
function main() {
    local command="$1"
    shift
    
    case "$command" in
        create)
            create_vms
            ;;
        destroy)
            destroy_vms
            ;;
        list)
            list_vms
            ;;
        update-api-vip)
            update_api_vip "$1"
            ;;
        *)
            log "Usage: $0 {create|destroy|list|update-api-vip <ip>}"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi