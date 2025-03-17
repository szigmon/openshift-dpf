#!/bin/bash

# Wait indefinitely for an interface to get an IP address and default route
WAIT_INTERVAL=5  # Check interval in seconds
ATTEMPT=1

echo "Waiting for network configuration..."
while true; do
    # Check if we have an interface with a default route
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

    if [ -n "$DEFAULT_INTERFACE" ]; then
        # Check if that interface has an IP address
        IP_ADDR=$(ip addr show dev "$DEFAULT_INTERFACE" | grep -w "inet" | awk '{print $2}')

        if [ -n "$IP_ADDR" ]; then
            echo "Network is ready. Interface $DEFAULT_INTERFACE has IP address $IP_ADDR"
            break
        fi
    fi

    echo "Waiting for network configuration... (Attempt $ATTEMPT)"
    sleep $WAIT_INTERVAL
    ATTEMPT=$((ATTEMPT + 1))
done

# Check if the bridge already exists
if ip link show br-dpu &>/dev/null; then
    echo "Bridge br-dpu already exists. No need to configure it."
    exit 0
fi

# Find the interface that has the default route
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

if [ -z "$DEFAULT_INTERFACE" ]; then
    echo "Error: Could not find interface with default route" >&2
    exit 1
fi

echo "Found default interface: $DEFAULT_INTERFACE"

# Create a temporary YAML file with the interface substituted
TMP_FILE=$(mktemp)

cat > "$TMP_FILE" << EOF
interfaces:
  - name: br-dpu
    type: linux-bridge
    state: up
    ipv6:
      enabled: false
    ipv4:
      enabled: true
      dhcp: true
      auto-dns: true
      auto-gateway: true
      auto-routes: true
    bridge:
      options:
        stp:
          enabled: false
      port:
        - name: $DEFAULT_INTERFACE
EOF

echo "Created NMState configuration with interface $DEFAULT_INTERFACE"
echo "Applying configuration using nmstatectl..."

# Apply the configuration
nmstatectl apply "$TMP_FILE"
RESULT=$?

# Clean up
rm "$TMP_FILE"

# Return the result
exit $RESULT
