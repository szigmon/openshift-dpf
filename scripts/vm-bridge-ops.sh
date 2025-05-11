#!/bin/bash
#
# Script to automatically create a Linux bridge on the interface that has the default route
# This script will:
# 1. Identify the interface with the default route
# 2. Create a bridge and attach that interface to it
# 3. Configure the bridge to use DHCP
#
# Usage: sudo ./create-bridge.sh [OPTION]
#        --force     Skip all confirmation prompts
#        --cleanup   Remove the bridge configuration
#
# Environment variables:
#        BRIDGE_NAME The name of the bridge to create (default: br0)

# Process command line arguments and environment variables

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
FORCE_MODE=false
CLEANUP_MODE=false
BRIDGE_NAME=${BRIDGE_NAME:-br0}  # Default to br0 if not set

if [ "$1" = "--force" ]; then
  FORCE_MODE=true
  echo "Force mode enabled. All confirmations will be skipped."
elif [ "$1" = "--cleanup" ]; then
  CLEANUP_MODE=true
  echo "Cleanup mode enabled. Bridge configuration will be removed."
fi

echo "Using bridge name: $BRIDGE_NAME"

# Exit on error
set -e

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to clean up NetworkManager configuration
cleanup_networkmanager() {
  echo "Cleaning up NetworkManager bridge configuration..."

  # Find bridge-slave connections for our specific bridge
  SLAVE_CONNECTIONS=$(nmcli -g NAME con show | grep "bridge-slave-.*-$BRIDGE_NAME" || true)

  # First, extract the physical interface name from the slave connection name
  if [ -n "$SLAVE_CONNECTIONS" ]; then
    # Take the first slave connection if there are multiple
    FIRST_SLAVE=$(echo "$SLAVE_CONNECTIONS" | head -n1)
    # Extract the interface name from the connection name (format: bridge-slave-INTERFACE-BRIDGE_NAME)
    PHYSICAL_INTERFACE=$(echo "$FIRST_SLAVE" | sed -E "s/bridge-slave-(.*)-$BRIDGE_NAME/\\1/")

    if [ -n "$PHYSICAL_INTERFACE" ]; then
      echo "Extracted physical interface from slave connection: $PHYSICAL_INTERFACE"
      DEFAULT_INTERFACE="$PHYSICAL_INTERFACE"
    fi
  fi

  # If we couldn't extract from connection name, try other methods
  if [ -z "$DEFAULT_INTERFACE" ]; then
    # Try to detect which interface is enslaved to the bridge
    DEFAULT_INTERFACE=$(bridge link show | grep $BRIDGE_NAME | awk '{print $2}' | head -n1)
    if [ -z "$DEFAULT_INTERFACE" ]; then
      echo "Warning: Could not identify the physical interface, proceeding anyway."
    else
      echo "Detected physical interface: $DEFAULT_INTERFACE"
    fi
  fi

  # Try to find and activate the original connection for default interface BEFORE removing the bridge
  if [ -n "$DEFAULT_INTERFACE" ]; then
    # Look for a regular ethernet connection for this interface
    # Filter out bridge, slave, virbr, docker and other virtual connection types
    ORIGINAL_CONN=$(nmcli -g NAME,DEVICE con show |
                    grep "$DEFAULT_INTERFACE" |
                    grep -v "bridge\|slave\|virbr\|docker\|veth\|tun\|tap" |
                    head -n1 |
                    cut -d: -f1)

    if [ -n "$ORIGINAL_CONN" ]; then
      echo "Activating original connection: $ORIGINAL_CONN"
      nmcli con up "$ORIGINAL_CONN" || true
      # Give it time to establish
      sleep 3
    else
      echo "No suitable original connection found for $DEFAULT_INTERFACE"
      echo "Creating a temporary DHCP connection to maintain connectivity"
      nmcli con add type ethernet con-name "temp-$DEFAULT_INTERFACE" ifname "$DEFAULT_INTERFACE" ipv4.method auto
      nmcli con up "temp-$DEFAULT_INTERFACE" || true
      # Give it time to establish
      sleep 3
    fi
  fi

  # Now down and delete all slave connections
  for CONN in $SLAVE_CONNECTIONS; do
    echo "Removing slave connection: $CONN"
    nmcli con down "$CONN" 2>/dev/null || true
    nmcli con delete "$CONN" 2>/dev/null || true
  done

  # Down and delete the bridge connection
  echo "Removing bridge connection: bridge-$BRIDGE_NAME"
  nmcli con down "bridge-$BRIDGE_NAME" 2>/dev/null || true
  nmcli con delete "bridge-$BRIDGE_NAME" 2>/dev/null || true

  echo "NetworkManager cleanup complete."
}

# Function to clean up Netplan configuration
cleanup_netplan() {
  echo "Cleaning up Netplan bridge configuration..."

  # First, restore backups if they exist
  NETPLAN_BACKUPS=$(find /etc/netplan -name "*.yaml.bak")
  for BACKUP in $NETPLAN_BACKUPS; do
    ORIGINAL="${BACKUP%.bak}"
    echo "Restoring $BACKUP to $ORIGINAL"
    cp "$BACKUP" "$ORIGINAL"
  done

  # Then apply the restored configuration first to ensure connectivity
  echo "Applying restored Netplan configuration..."
  netplan apply

  # Give it time to establish
  sleep 3

  # Now, remove our bridge configuration file
  if [ -f "/etc/netplan/99-bridge-$BRIDGE_NAME.yaml" ]; then
    echo "Removing /etc/netplan/99-bridge-$BRIDGE_NAME.yaml"
    rm "/etc/netplan/99-bridge-$BRIDGE_NAME.yaml"
  fi

  # Remove backup files
  for BACKUP in $NETPLAN_BACKUPS; do
    echo "Removing backup: $BACKUP"
    rm "$BACKUP"
  done

  echo "Netplan cleanup complete."
}

# Function to configure using NetworkManager
configure_with_networkmanager() {
  echo "Creating bridge with NetworkManager..."

  # Create the bridge
  nmcli con add type bridge con-name bridge-$BRIDGE_NAME ifname $BRIDGE_NAME
  nmcli con mod bridge-$BRIDGE_NAME bridge.stp no

  # Get the current connection name for the interface
  CONN_NAME=$(nmcli -g NAME,DEVICE connection show --active | grep "$DEFAULT_INTERFACE" | cut -d: -f1)

  if [ -z "$CONN_NAME" ]; then
    echo "Warning: Could not find active connection for $DEFAULT_INTERFACE"
    # Try to get any connection for this device
    CONN_NAME=$(nmcli -g NAME,DEVICE connection show | grep "$DEFAULT_INTERFACE" | head -n1 | cut -d: -f1)

    if [ -z "$CONN_NAME" ]; then
      echo "Error: No connection found for $DEFAULT_INTERFACE"
      exit 1
    fi
  fi

  echo "Found connection: $CONN_NAME for interface $DEFAULT_INTERFACE"

  # Configure bridge for DHCP only
  echo "Configuring bridge to use DHCP"
  nmcli con mod bridge-$BRIDGE_NAME ipv4.method auto

  # Create the slave connection with bridge name in the connection name
  nmcli con add type bridge-slave con-name bridge-slave-"$DEFAULT_INTERFACE-$BRIDGE_NAME" ifname "$DEFAULT_INTERFACE" master $BRIDGE_NAME

  echo "NetworkManager configurations created. Ready to activate."

  if [ "$FORCE_MODE" = false ]; then
    echo "WARNING: The next step will change your network configuration."
    echo "If you're connected via SSH on this interface, you might lose connectivity."
    echo "Make sure you have an alternative way to access the system if needed."
    read -p "Continue? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Bridge setup paused before activation."
      echo "To activate manually, run:"
      echo "  sudo nmcli con up bridge-$BRIDGE_NAME"
      echo "  sudo nmcli con down \"$CONN_NAME\""
      echo "  sudo nmcli con up bridge-slave-$DEFAULT_INTERFACE-$BRIDGE_NAME"
      exit 0
    fi
  fi

  echo "Activating bridge..."

  # Activate the bridge first
  nmcli con up bridge-$BRIDGE_NAME

  # Wait a bit for the bridge to initialize
  sleep 5

  # Deactivate the original connection
  nmcli con down "$CONN_NAME"

  # Activate the slave connection
  nmcli con up bridge-slave-"$DEFAULT_INTERFACE-$BRIDGE_NAME"

  echo "Bridge activation complete."
}

# Function to configure using Netplan
configure_with_netplan() {
  echo "Creating bridge with Netplan..."

  # Create a backup of existing configuration
  NETPLAN_FILES=$(find /etc/netplan -name "*.yaml")
  for file in $NETPLAN_FILES; do
    cp "$file" "$file.bak"
    echo "Backed up $file to $file.bak"
  done

  # Create new configuration file
  cat > /etc/netplan/99-bridge-$BRIDGE_NAME.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $DEFAULT_INTERFACE:
      dhcp4: no
  bridges:
    $BRIDGE_NAME:
      interfaces: [$DEFAULT_INTERFACE]
      dhcp4: yes
EOF

  echo "Netplan configuration created."

  if [ "$FORCE_MODE" = false ]; then
    echo "WARNING: The next step will change your network configuration."
    echo "If you're connected via SSH on this interface, you might lose connectivity."
    echo "Make sure you have an alternative way to access the system if needed."
    read -p "Continue with 'netplan try'? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Bridge setup paused before activation."
      echo "To activate manually, run:"
      echo "  sudo netplan try"
      echo "  sudo netplan apply"
      exit 0
    fi
  fi

  echo "Trying new configuration (will automatically revert if not confirmed within 120 seconds)..."
  netplan try
  echo "Configuration applied successfully."
}

# Main execution flow starts here
if [ "$CLEANUP_MODE" = true ]; then
  # Detect the interface with the default route (for reference in cleanup)
  DEFAULT_INTERFACE=$(ip route | grep default | head -n1 | awk '{print $5}')

  if [ -z "$DEFAULT_INTERFACE" ]; then
    echo "Warning: Could not identify the default interface, continuing anyway."
  else
    echo "Default route uses interface: $DEFAULT_INTERFACE"
    echo "Current IP configuration: $(ip -o -4 addr show dev "$DEFAULT_INTERFACE" | awk '{print $4}'), Gateway: $(ip route | grep default | head -n1 | awk '{print $3}')"
  fi

  # Detect which network manager is in use
  if command_exists nmcli && systemctl is-active --quiet NetworkManager; then
    echo "NetworkManager detected"
    cleanup_networkmanager
  elif [ -d /etc/netplan ]; then
    echo "Netplan detected"
    cleanup_netplan
  else
    echo "Error: Unsupported network configuration system"
    echo "This script only supports NetworkManager and Netplan"
    exit 1
  fi

  echo "Bridge cleanup complete."
  exit 0
else
  # Normal bridge creation flow - detect the default interface
  DEFAULT_INTERFACE=$(ip route | grep default | head -n1 | awk '{print $5}')

  if [ -z "$DEFAULT_INTERFACE" ]; then
    echo "Error: Could not identify the default interface"
    exit 1
  fi

  echo "Default route uses interface: $DEFAULT_INTERFACE"
  echo "Current IP configuration: $(ip -o -4 addr show dev "$DEFAULT_INTERFACE" | awk '{print $4}'), Gateway: $(ip route | grep default | head -n1 | awk '{print $3}')"

  # Detect which network manager is in use
  USING_NETWORKMANAGER=false
  USING_NETPLAN=false

  if command_exists nmcli && systemctl is-active --quiet NetworkManager; then
    echo "NetworkManager detected"
    USING_NETWORKMANAGER=true
  elif [ -d /etc/netplan ]; then
    echo "Netplan detected"
    USING_NETPLAN=true
  else
    echo "Error: Unsupported network configuration system"
    echo "This script only supports NetworkManager and Netplan"
    exit 1
  fi

  # Create the bridge
  echo "Creating bridge br0 on interface $DEFAULT_INTERFACE..."

  # Configure based on detected network manager
  if [ "$USING_NETWORKMANAGER" = true ]; then
    configure_with_networkmanager
  elif [ "$USING_NETPLAN" = true ]; then
    configure_with_netplan
  else
    echo "Error: Only NetworkManager and Netplan are supported in this script."
    echo "Your system appears to be using a legacy network configuration system."
    exit 1
  fi

  echo "Bridge setup complete."
  echo "You can now use bridge=br0 in your VM configuration."
fi
