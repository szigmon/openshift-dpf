#!/bin/bash
set -e

# Default configuration
VM_PREFIX=${VM_PREFIX:-"vm-dpf"}
DEFAULT_POOL=${DEFAULT_POOL:-"images"}

# 1. Delete all VMs whose names start with VM_PREFIX
echo "Deleting all VMs starting with prefix: $VM_PREFIX"

# List all VMs (running or stopped) whose names start with VM_PREFIX
for vm in $(virsh list --all --name | grep "^${VM_PREFIX}" || true); do
    echo "Deleting VM: $vm"
    # Attempt to destroy the VM if it is running
    virsh destroy "$vm" || echo "VM $vm is not running"
    # Undefine (remove) the VM from libvirt
    virsh undefine "$vm"

    echo "VM $vm deleted."
    echo
done

echo "All VMs with prefix '$VM_PREFIX' have been processed."

# 2. Delete all volumes in the DEFAULT_POOL whose names start with VM_PREFIX
echo "Deleting all volumes in pool '$DEFAULT_POOL' starting with prefix: $VM_PREFIX"

# List all volumes in the DEFAULT_POOL and grep for VM_PREFIX
for vol in $(virsh vol-list --pool "$DEFAULT_POOL" --details | awk '{print $1}' | grep "^${VM_PREFIX}" || true); do
    echo "Deleting volume: $vol"
    virsh vol-delete "$vol" --pool "$DEFAULT_POOL"
    echo "Volume $vol deleted."
    echo
done

echo "All volumes with prefix '$VM_PREFIX' have been deleted from pool '$DEFAULT_POOL'."