#!/bin/bash
set -e

# Configuration with defaults
VM_PREFIX=${VM_PREFIX:-"vm-dpf"}
VM_COUNT=${VM_COUNT:-3}

# Get the default physical NIC
PHYSICAL_NIC=${PHYSICAL_NIC:-$(ip route | awk '/default/ {print $5; exit}')}
RAM=${RAM:-16384}  # Memory in MB
VCPUS=${VCPUS:-8}   # Number of virtual CPUs
DISK_SIZE1=${DISK_SIZE1:-120}  # Size of first disk
DISK_SIZE2=${DISK_SIZE2:-40}  # Size of second disk
DISK_PATH=${DISK_PATH:-"/var/lib/libvirt/images"}
ISO_PATH=${ISO_PATH:-"/var/lib/libvirt/images/discovery_image_test-dpf-mno.iso"}

for i in $(seq 1 "$VM_COUNT"); do
    VM_NAME="${VM_PREFIX}${i}"
    echo "Creating VM: $VM_NAME"
    nohup virt-install --name "$VM_NAME" --memory $RAM \
            --vcpus "$VCPUS" \
            --os-variant=rhel9.4 \
            --disk pool=default,size="${DISK_SIZE1}" \
            --disk pool=default,size="${DISK_SIZE2}" \
            --network type=direct,source="${PHYSICAL_NIC}",source_mode=bridge,model=virtio \
            --graphics=vnc \
            --events on_reboot=restart \
            --cdrom "$ISO_PATH" \
            --cpu host-passthrough \
            --noautoconsole \
            --wait=-1 &


done

echo "All VMs have been created successfully."
