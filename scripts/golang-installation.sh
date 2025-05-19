#!/bin/bash
# Script to install the latest Go version on Linux
# Run with sudo

set -e

echo "Checking for existing Go installation..."

# Check if Go is already installed
if command -v go >/dev/null 2>&1; then
    echo "Go is already installed. No need for installation."
    go version
    exit 0
fi

echo "Go is not installed. Proceeding with installation..."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script needs sudo privileges. Please run with sudo."
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    GOARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    GOARCH="arm64"
else
    echo "Architecture $ARCH may not be supported"
    # We'll still try to continue with amd64
    GOARCH="amd64"
fi

# Get latest version
LATEST_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
LATEST_VERSION=${LATEST_VERSION#go}

echo "Downloading Go $LATEST_VERSION for $GOARCH..."
wget -q --show-progress -O /tmp/go.tar.gz https://dl.google.com/go/go${LATEST_VERSION}.linux-${GOARCH}.tar.gz

# Install Go to standard location
echo "Installing Go to /usr/local/go..."
tar -C /usr/local -xzf /tmp/go.tar.gz
rm -f /tmp/go.tar.gz

# Create symlinks in /usr/bin
echo "Creating symlinks to Go executables in /usr/bin..."
ln -sf /usr/local/go/bin/go /usr/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt

echo "Go $LATEST_VERSION installed successfully!"
go version
