#!/bin/bash
set -e

# Configuration with defaults
VM_PREFIX=${VM_PREFIX:-"vm-dpf"}
VM_COUNT=${VM_COUNT:-3}
MTU_SIZE=${MTU_SIZE:-1500}

# Get the default physical NIC
PHYSICAL_NIC=${PHYSICAL_NIC:-$(ip route | awk '/default/ {print $5; exit}')}
API_VIP=${API_VIP}
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
            --network type=direct,source="${PHYSICAL_NIC}",mac="52:54:00:12:34:5${i}",source_mode=bridge,model=virtio \
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

echo "All VMs created and running successfully"