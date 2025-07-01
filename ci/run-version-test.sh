#!/bin/bash

# Manual trigger script for DPF version testing
# This script simulates the CI workflow locally

set -euo pipefail

# Default values
DPF_VERSION=""
OPENSHIFT_VERSION="4.17.3"
CLUSTER_NAME="dpf-local-test"
SKIP_CLEANUP="false"
SKIP_DEPLOY="false"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] <dpf-version>

Run DPF version tests locally

Arguments:
    dpf-version          DPF version to test (e.g., v25.4.0)

Options:
    -o, --openshift      OpenShift version (default: $OPENSHIFT_VERSION)
    -c, --cluster        Cluster name (default: $CLUSTER_NAME)
    -s, --skip-cleanup   Skip cluster cleanup after test
    -d, --skip-deploy    Skip cluster deployment (use existing)
    -h, --help          Show this help message

Examples:
    $0 v25.4.0
    $0 --openshift 4.17.3 --cluster test-cluster v25.4.0
    $0 --skip-deploy --skip-cleanup v25.4.0

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--openshift)
            OPENSHIFT_VERSION="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -s|--skip-cleanup)
            SKIP_CLEANUP="true"
            shift
            ;;
        -d|--skip-deploy)
            SKIP_DEPLOY="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            DPF_VERSION="$1"
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$DPF_VERSION" ]; then
    echo -e "${RED}Error: DPF version is required${NC}"
    usage
    exit 1
fi

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[${timestamp}]${NC} ${message}"
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}]${NC} ${message}"
            ;;
        ERROR)
            echo -e "${RED}[${timestamp}]${NC} ${message}"
            ;;
        STEP)
            echo -e "${BLUE}[${timestamp}]${NC} >>> ${message}"
            ;;
    esac
}

# Function to run command with logging
run_cmd() {
    local cmd="$*"
    log INFO "Running: $cmd"
    eval "$cmd"
}

# Generate test ID
TEST_ID="manual-$(date +%Y%m%d-%H%M%S)"
TEST_DIR="${PROJECT_ROOT}/test-results/${TEST_ID}"

log INFO "Starting DPF Version Test"
log INFO "========================="
log INFO "DPF Version: $DPF_VERSION"
log INFO "OpenShift Version: $OPENSHIFT_VERSION"
log INFO "Cluster Name: $CLUSTER_NAME"
log INFO "Test ID: $TEST_ID"
log INFO "Skip Cleanup: $SKIP_CLEANUP"
log INFO "Skip Deploy: $SKIP_DEPLOY"

# Create test directory
mkdir -p "$TEST_DIR"

# Step 1: Check if version needs testing
log STEP "Checking version status"
cd "$PROJECT_ROOT"

if ./ci/scripts/version-detector.sh check "$DPF_VERSION"; then
    log WARN "Version $DPF_VERSION is already tested. Continue anyway? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log INFO "Aborted by user"
        exit 0
    fi
fi

# Step 2: Compare with current version
log STEP "Comparing versions"
CURRENT_VERSION=$(./ci/scripts/version-detector.sh current)
log INFO "Current version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "$DPF_VERSION" ]; then
    python3 ci/scripts/version-compare.py \
        --old-version "$CURRENT_VERSION" \
        --new-version "$DPF_VERSION" \
        --output "$TEST_DIR/version-comparison.md" || {
        log WARN "Version comparison failed, continuing anyway"
    }
fi

# Step 3: Update manifests
log STEP "Updating manifests to $DPF_VERSION"

# Create a test branch
TEST_BRANCH="test/${TEST_ID}"
git checkout -b "$TEST_BRANCH" || {
    log ERROR "Failed to create test branch"
    exit 1
}

# Update versions
python3 ci/update/version-updater.py "$DPF_VERSION" \
    --report "$TEST_DIR/update-report.md" || {
    log ERROR "Failed to update versions"
    git checkout -
    git branch -D "$TEST_BRANCH"
    exit 1
}

# Commit changes
git add -A
git commit -m "test: Update to DPF $DPF_VERSION" || {
    log INFO "No changes to commit"
}

# Step 4: Deploy cluster (if not skipped)
if [ "$SKIP_DEPLOY" = "false" ]; then
    log STEP "Deploying OpenShift cluster"
    
    # Update .env file
    cp .env.example .env
    sed -i.bak "s/CLUSTER_NAME=.*/CLUSTER_NAME=$CLUSTER_NAME/" .env
    sed -i.bak "s/OPENSHIFT_VERSION=.*/OPENSHIFT_VERSION=$OPENSHIFT_VERSION/" .env
    
    # Create cluster
    make create-cluster || {
        log ERROR "Cluster creation failed"
        exit 1
    }
    
    # Install cluster
    make cluster-install || {
        log ERROR "Cluster installation failed"
        exit 1
    }
    
    # Get kubeconfig
    make kubeconfig
else
    log INFO "Skipping cluster deployment"
    
    # Ensure we have kubeconfig
    if [ ! -f "${PROJECT_ROOT}/kubeconfig" ]; then
        make kubeconfig || {
            log ERROR "Failed to get kubeconfig"
            exit 1
        }
    fi
fi

export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Step 5: Deploy DPF
log STEP "Deploying DPF $DPF_VERSION"

make deploy-dpf || {
    log ERROR "DPF deployment failed"
    oc get pods -n dpf-operator-system > "$TEST_DIR/dpf-pods-failed.txt"
    exit 1
}

# Wait for operator to be ready
log INFO "Waiting for DPF operator to be ready..."
oc wait --for=condition=ready pod -l app.kubernetes.io/name=dpf-operator \
    -n dpf-operator-system --timeout=300s || {
    log ERROR "DPF operator failed to become ready"
    exit 1
}

# Step 6: Deploy DPU services
log STEP "Deploying DPU services"

make prepare-dpu-files
make deploy-dpu-services || {
    log WARN "DPU services deployment had issues"
}

# Step 7: Run tests
log STEP "Running validation tests"

# Run API compatibility tests
log INFO "Running API compatibility tests..."
./ci/tests/api-compatibility-test.sh "$DPF_VERSION" \
    > "$TEST_DIR/api-compatibility.log" 2>&1 || {
    log ERROR "API compatibility tests failed"
    cat "$TEST_DIR/api-compatibility.log"
}

# Run service validation tests
log INFO "Running service validation tests..."
./ci/tests/service-validation.sh \
    > "$TEST_DIR/service-validation.log" 2>&1 || {
    log WARN "Service validation had issues"
}

# Step 8: Collect results
log STEP "Collecting test results"

# Collect cluster information
oc get nodes > "$TEST_DIR/nodes.txt"
oc get pods -A > "$TEST_DIR/pods.txt"
oc get events -A --sort-by='.lastTimestamp' | head -100 > "$TEST_DIR/events.txt"

# Collect DPF information
oc get crd | grep -E 'dpu|dpf' > "$TEST_DIR/dpf-crds.txt" || true
oc get all -n dpf-operator-system > "$TEST_DIR/dpf-operator.txt" || true
oc get dpuservicetemplate -A > "$TEST_DIR/dpuservicetemplates.txt" || true
oc get dpudeployment -A > "$TEST_DIR/dpudeployments.txt" || true

# Generate summary
cat > "$TEST_DIR/summary.md" << EOF
# DPF Version Test Summary

**Test ID**: $TEST_ID
**DPF Version**: $DPF_VERSION
**OpenShift Version**: $OPENSHIFT_VERSION
**Cluster**: $CLUSTER_NAME
**Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Test Results

- Cluster Deployment: $([ "$SKIP_DEPLOY" = "true" ] && echo "Skipped" || echo "Success")
- DPF Deployment: Success
- API Compatibility: $(grep -q "PASSED" "$TEST_DIR/api-compatibility.log" 2>/dev/null && echo "✅ Passed" || echo "❌ Failed")
- Service Validation: $(grep -q "PASSED" "$TEST_DIR/service-validation.log" 2>/dev/null && echo "✅ Passed" || echo "⚠️ Issues")

## Cluster Status

\`\`\`
$(oc get nodes 2>/dev/null || echo "Cluster not accessible")
\`\`\`

## DPF Components

\`\`\`
$(oc get pods -n dpf-operator-system 2>/dev/null || echo "DPF namespace not found")
\`\`\`

## Test Artifacts

All test results are saved in: $TEST_DIR
EOF

# Step 9: Cleanup
if [ "$SKIP_CLEANUP" = "false" ]; then
    log STEP "Cleaning up"
    
    if [ "$SKIP_DEPLOY" = "false" ]; then
        make delete-cluster || {
            log WARN "Cluster deletion failed"
        }
    fi
    
    # Return to main branch
    git checkout -
    git branch -D "$TEST_BRANCH" || true
else
    log INFO "Skipping cleanup - test branch: $TEST_BRANCH"
fi

# Step 10: Display results
log STEP "Test Complete!"
echo ""
cat "$TEST_DIR/summary.md"
echo ""
log INFO "Full results saved to: $TEST_DIR"

# Check if tests passed
if grep -q "PASSED" "$TEST_DIR/api-compatibility.log" 2>/dev/null; then
    log INFO "✅ Version $DPF_VERSION is compatible!"
    exit 0
else
    log ERROR "❌ Version $DPF_VERSION has compatibility issues"
    exit 1
fi