#!/bin/bash
# test-worker-iso.sh - Test worker ISO download functionality

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "Checking prerequisites..."

# Check if aicli is installed
if ! command_exists aicli; then
    error_exit "aicli not found. Please install the Assisted Installer CLI: pip install aicli"
fi

# Check if make is installed
if ! command_exists make; then
    error_exit "make not found. Please install make"
fi

echo "Testing worker ISO functionality..."

# Step 1: Create day2 cluster
echo "Step 1: Creating day2 cluster..."
if ! make create-day2-cluster; then
    warning "Day2 cluster creation failed, but continuing with test"
fi

# Step 2: Get worker ISO URL (minimal)
echo "Step 2: Getting minimal worker ISO URL..."
if make get-worker-iso ISO_TYPE=minimal; then
    success "Got minimal worker ISO URL"
else
    warning "Failed to get minimal worker ISO URL, continuing with test"
fi

# Step 3: Get worker ISO URL (full)
echo "Step 3: Getting full worker ISO URL..."
if make get-worker-iso ISO_TYPE=full; then
    success "Got full worker ISO URL"
else
    warning "Failed to get full worker ISO URL, continuing with test"
fi

# Create test output dir
TEST_OUTPUT_DIR="/tmp/dpf-iso-test"
mkdir -p "$TEST_OUTPUT_DIR"

# Step 4: Download minimal worker ISO to a custom location
echo "Step 4: Downloading minimal worker ISO to test directory..."
if make create-cluster-iso ISO_TYPE=minimal ISO_OUTPUT="$TEST_OUTPUT_DIR/worker-minimal.iso" NON_INTERACTIVE=true; then
    success "Downloaded minimal worker ISO"
else
    warning "Failed to download minimal worker ISO, continuing with test"
fi

# Step 5: Download full worker ISO to a custom location
echo "Step 5: Downloading full worker ISO to test directory..."
if make create-cluster-iso ISO_TYPE=full ISO_OUTPUT="$TEST_OUTPUT_DIR/worker-full.iso" NON_INTERACTIVE=true; then
    success "Downloaded full worker ISO"
else
    warning "Failed to download full worker ISO, continuing with test"
fi

# Step 6: Verify ISO files
echo "Step 6: Verifying ISO files..."
iso_found=false

if [ -f "$TEST_OUTPUT_DIR/worker-minimal.iso" ]; then
    success "Minimal worker ISO downloaded successfully: $TEST_OUTPUT_DIR/worker-minimal.iso"
    ls -lh "$TEST_OUTPUT_DIR/worker-minimal.iso"
    iso_found=true
else
    warning "Minimal worker ISO not found or download failed"
fi

if [ -f "$TEST_OUTPUT_DIR/worker-full.iso" ]; then
    success "Full worker ISO downloaded successfully: $TEST_OUTPUT_DIR/worker-full.iso"
    ls -lh "$TEST_OUTPUT_DIR/worker-full.iso"
    iso_found=true
else
    warning "Full worker ISO not found or download failed"
fi

# Step 7: Test overwriting existing ISO in non-interactive mode if any ISO was downloaded
if [ "$iso_found" = true ]; then
    echo "Step 7: Testing overwrite of existing ISO in non-interactive mode..."
    if [ -f "$TEST_OUTPUT_DIR/worker-minimal.iso" ]; then
        if make create-cluster-iso ISO_TYPE=minimal ISO_OUTPUT="$TEST_OUTPUT_DIR/worker-minimal.iso" NON_INTERACTIVE=true; then
            success "Successfully tested overwrite functionality"
        else
            warning "Failed to test overwrite functionality"
        fi
    fi
else
    warning "Skipping overwrite test as no ISO files were successfully downloaded"
fi

# Only proceed to default output location test if at least one ISO download succeeded
if [ "$iso_found" = true ]; then
    echo "All tests completed. At least some features of worker ISO functionality are working."
else
    warning "No ISO files were downloaded successfully. The worker ISO functionality may not be working correctly."
    warning "Please check your aicli configuration, OpenShift authentication, and cluster status."
    exit 1
fi 