#!/bin/bash
# vm.sh - Virtual Machine Management

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# -----------------------------------------------------------------------------
# VM Management Functions
# -----------------------------------------------------------------------------
function create_vms() {
    log "Creating VMs with prefix $VM_PREFIX..."
    
    # Create primary disk for each VM
    for i in $(seq 1 $VM_COUNT); do
        log "Creating primary disk for ${VM_PREFIX}-$i"
        qemu-img create -f qcow2 ${DISK_PATH}/${VM_PREFIX}-$i.qcow2 ${DISK_SIZE1}G
    done

    # Create secondary disk for each VM
    for i in $(seq 1 $VM_COUNT); do
        log "Creating secondary disk for ${VM_PREFIX}-$i"
        qemu-img create -f qcow2 ${DISK_PATH}/${VM_PREFIX}-$i-2.qcow2 ${DISK_SIZE2}G
    done

    # Create VMs
    for i in $(seq 1 $VM_COUNT); do
        log "Creating VM ${VM_PREFIX}-$i"
        virt-install \
            --name=${VM_PREFIX}-$i \
            --ram=${RAM} \
            --vcpus=${VCPUS} \
            --cpu host-passthrough \
            --os-type linux \
            --os-variant rhel8.0 \
            --network type=direct,source="${PHYSICAL_NIC}",mac="52:54:00:12:34:5${i}",source_mode=bridge,model=virtio \
            --network network=default \
            --network network=default,model=virtio \
            --graphics none \
            --noautoconsole \
            --location=${ISO_FOLDER}/rhcos-live.x86_64.iso,kernel=images/pxeboot/vmlinuz,initrd=images/pxeboot/initramfs.img \
            --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.live.rootfs_url=http://192.168.122.1:8080/rhcos-rootfs coreos.inst.insecure=yes coreos.inst.ignition_url=http://192.168.122.1:8080/bootstrap.ign" \
            --disk path=${DISK_PATH}/${VM_PREFIX}-$i.qcow2,device=disk,bus=virtio,format=qcow2 \
            --disk path=${DISK_PATH}/${VM_PREFIX}-$i-2.qcow2,device=disk,bus=virtio,format=qcow2 \
            --memorybacking hugepages=on
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
        if ! virsh undefine ${vm} 2>/dev/null; then
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