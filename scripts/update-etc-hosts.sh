#!/bin/bash

# Constants
HOSTS_FILE="/etc/hosts"
PING_TIMEOUT=2
PING_COUNT=1

# Print usage information
print_usage() {
    echo "Usage: $0 <ip_address> <fqdn> [vm_prefix]"
    echo "Example: $0 192.168.1.100 myserver.example.com"
    echo "Example with VM prefix: $0 192.168.1.100 myserver.example.com myvm"
}

# Check if script is run with sudo/root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run with sudo privileges"
        exit 1
    fi
}

# Validate command line arguments
validate_args() {
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        print_usage
        exit 1
    fi
}

# Check if an IP is reachable
check_ip_reachable() {
    local ip=$1
    ping -c $PING_COUNT -W $PING_TIMEOUT "$ip" >/dev/null 2>&1
    return $?
}

# Get list of VMs matching prefix
get_matching_vms() {
    local vm_prefix=$1
    virsh list --all | grep "$vm_prefix" | awk '{print $2}'
}

# Get IP address for a specific VM
get_vm_ip() {
    local vm_name=$1
    virsh domifaddr "$vm_name" 2>/dev/null | grep -v "^$" | tail -n +3 | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1
}

# Find IP address for any VM matching prefix
find_vm_ip() {
    local vm_prefix=$1
    local vm_ip=""

    echo "Looking for VMs matching prefix: $vm_prefix"
    local vm_list=$(get_matching_vms "$vm_prefix")

    if [ -z "$vm_list" ]; then
        echo "No VMs found matching prefix: $vm_prefix"
        return 1
    fi

    echo "Found VMs:"
    echo "$vm_list"

    for vm in $vm_list; do
        echo "Checking IP for VM: $vm"
        vm_ip=$(get_vm_ip "$vm")
        if [ -n "$vm_ip" ]; then
            echo "Found IP: $vm_ip for VM: $vm"
            echo "$vm_ip"
            return 0
        fi
    done

    echo "No IP addresses found for matching VMs"
    return 1
}

# Update hosts file entry
update_hosts_file() {
    local ip=$1
    local fqdn=$2
    local temp_file=$(mktemp)
    local updated=0

    # Read hosts file line by line and update/add entry
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ ^[^#]*[[:space:]]+"$fqdn"([[:space:]]|$) ]]; then
            echo "$ip $fqdn" >> "$temp_file"
            updated=1
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$HOSTS_FILE"

    # If FQDN wasn't found, append new entry
    if [ $updated -eq 0 ]; then
        echo "$ip $fqdn" >> "$temp_file"
    fi

    # Backup original hosts file
    cp "$HOSTS_FILE" "${HOSTS_FILE}.bak"

    # Replace original hosts file
    cat "$temp_file" > "$HOSTS_FILE"
    rm "$temp_file"

    echo "Updated $HOSTS_FILE (Backup created at ${HOSTS_FILE}.bak)"
    echo "New entry:"
    grep -E "^[^#]*[[:space:]]$fqdn([[:space:]]|$)" "$HOSTS_FILE" || true
}

# Main function
main() {
    local ip=$1
    local fqdn=$2
    local vm_prefix=${3:-""}

    if ! check_ip_reachable "$ip"; then
        echo "Warning: IP $ip is not reachable"

        if [ -n "$vm_prefix" ]; then
            echo "Attempting to find VM IP for prefix: $vm_prefix"
            local vm_ip=$(find_vm_ip "$vm_prefix")

            if [ -n "$vm_ip" ]; then
                echo "Found VM IP: $vm_ip"
                ip=$vm_ip
            else
                echo "Error: Could not find VM IP for prefix $vm_prefix"
                echo "Using original IP: $ip"
            fi
        else
            echo "No VM prefix provided. Using original IP."
        fi
    fi

    update_hosts_file "$ip" "$fqdn"
}

# Script execution starts here
check_root
validate_args "$@"
main "$@"