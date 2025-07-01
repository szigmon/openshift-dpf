#!/bin/bash

# Test Orchestrator for DPF CI
# Manages both local comparison tests and remote hardware tests

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$CI_DIR")"

# Test modes
MODE="${1:-full}"  # quick, full, hardware-only
DPF_VERSION="${2:-}"

# Results directory
RESULTS_DIR="${PROJECT_ROOT}/test-results/orchestrated-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    echo -e "${!level}[$(date '+%Y-%m-%d %H:%M:%S')] $message${NC}" | tee -a "$RESULTS_DIR/orchestrator.log"
}

# Phase 1: Quick local tests (no hardware needed)
run_quick_tests() {
    log GREEN "Phase 1: Running quick local tests"
    
    # 1.1 Version detection
    log BLUE "Running version detection..."
    if [ -z "$DPF_VERSION" ]; then
        NEW_VERSIONS=$("$CI_DIR/scripts/version-detector.sh" detect | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
        if [ -n "$NEW_VERSIONS" ]; then
            DPF_VERSION=$(echo "$NEW_VERSIONS" | head -1)
            log GREEN "Detected new version: $DPF_VERSION"
        else
            log YELLOW "No new versions detected"
            return 1
        fi
    fi
    
    # 1.2 Version comparison
    log BLUE "Running version comparison..."
    CURRENT_VERSION=$("$CI_DIR/scripts/version-detector.sh" current)
    
    if [ "$CURRENT_VERSION" != "$DPF_VERSION" ]; then
        python3 "$CI_DIR/scripts/version-compare.py" \
            --old-version "$CURRENT_VERSION" \
            --new-version "$DPF_VERSION" \
            --output "$RESULTS_DIR/version-comparison.md" || {
            log YELLOW "Version comparison completed with warnings"
        }
    fi
    
    # 1.3 Manifest validation
    log BLUE "Validating manifest updates..."
    python3 "$CI_DIR/update/version-updater.py" "$DPF_VERSION" \
        --dry-run \
        --report "$RESULTS_DIR/manifest-updates.md" || {
        log RED "Manifest update validation failed"
        return 1
    }
    
    # 1.4 Documentation analysis
    log BLUE "Analyzing documentation..."
    if command -v python3 &>/dev/null; then
        python3 "$CI_DIR/docs/rdg-parser.py" \
            --output "$RESULTS_DIR/rdg-analysis.md" \
            --json > "$RESULTS_DIR/rdg-config.json" || {
            log YELLOW "Documentation parsing completed with warnings"
        }
    fi
    
    log GREEN "Quick tests completed successfully"
    return 0
}

# Phase 2: Full hardware deployment test
run_hardware_tests() {
    log GREEN "Phase 2: Running hardware deployment tests"
    
    # Check if remote access is configured
    if [ -z "${SSH_HOST:-}" ]; then
        log YELLOW "SSH_HOST not configured, skipping hardware tests"
        return 1
    fi
    
    # 2.1 Deploy on hardware
    log BLUE "Starting remote deployment..."
    "$CI_DIR/scripts/remote-deployment.sh" "$DPF_VERSION" | tee "$RESULTS_DIR/remote-deployment.log"
    
    # 2.2 Wait for deployment info
    if [ -f "deployment-info.json" ]; then
        cp deployment-info.json "$RESULTS_DIR/"
        DEPLOYMENT_ID=$(jq -r '.deployment_id' deployment-info.json)
        REMOTE_DIR=$(jq -r '.remote_dir' deployment-info.json)
        
        log GREEN "Deployment ID: $DEPLOYMENT_ID"
        log GREEN "Remote directory: $REMOTE_DIR"
    else
        log RED "Failed to get deployment information"
        return 1
    fi
    
    # 2.3 Monitor deployment progress
    log BLUE "Monitoring deployment progress..."
    
    # Create monitoring script
    cat > "$RESULTS_DIR/monitor-deployment.sh" << EOF
#!/bin/bash
# Monitor script for deployment: $DEPLOYMENT_ID

SSH_USER="${SSH_USER:-root}"
SSH_HOST="$SSH_HOST"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-}"
REMOTE_DIR="$REMOTE_DIR"

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no \\
        -o UserKnownHostsFile=/dev/null \\
        -p "\$SSH_PORT" \\
        \${SSH_KEY:+-i "\$SSH_KEY"} \\
        "\$SSH_USER@\$SSH_HOST" \\
        "\$@"
}

echo "Checking deployment status..."
ssh_cmd "\$REMOTE_DIR/check-status.sh \$REMOTE_DIR/openshift-dpf/kubeconfig"

echo -e "\\nCSR Monitor logs (last 20 lines):"
ssh_cmd "tail -20 \$REMOTE_DIR/csr-monitor.log 2>/dev/null || echo 'No CSR monitor logs yet'"

echo -e "\\nWaiting for DPUs..."
ssh_cmd "cd \$REMOTE_DIR/openshift-dpf && export KUBECONFIG=kubeconfig && oc get dpu -A -w"
EOF
    
    chmod +x "$RESULTS_DIR/monitor-deployment.sh"
    
    log GREEN "Hardware deployment initiated"
    log YELLOW "Monitor deployment with: $RESULTS_DIR/monitor-deployment.sh"
    
    return 0
}

# Phase 3: Automated validation (runs after hardware is ready)
run_validation_tests() {
    log GREEN "Phase 3: Running validation tests"
    
    if [ -z "${SSH_HOST:-}" ] || [ ! -f "$RESULTS_DIR/deployment-info.json" ]; then
        log YELLOW "Skipping validation - no hardware deployment found"
        return 1
    fi
    
    REMOTE_DIR=$(jq -r '.remote_dir' "$RESULTS_DIR/deployment-info.json")
    
    # 3.1 Run API compatibility tests remotely
    log BLUE "Running API compatibility tests..."
    ssh_cmd() {
        ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -p "${SSH_PORT:-22}" \
            ${SSH_KEY:+-i "$SSH_KEY"} \
            "${SSH_USER:-root}@$SSH_HOST" \
            "$@"
    }
    
    ssh_cmd "cd $REMOTE_DIR/openshift-dpf && export KUBECONFIG=kubeconfig && ./ci/tests/api-compatibility-test.sh '$DPF_VERSION'" \
        > "$RESULTS_DIR/api-compatibility.log" 2>&1 || {
        log RED "API compatibility tests failed"
    }
    
    # 3.2 Run service validation tests
    log BLUE "Running service validation tests..."
    ssh_cmd "cd $REMOTE_DIR/openshift-dpf && export KUBECONFIG=kubeconfig && ./ci/tests/service-validation.sh" \
        > "$RESULTS_DIR/service-validation.log" 2>&1 || {
        log YELLOW "Service validation completed with warnings"
    }
    
    # 3.3 Collect results
    log BLUE "Collecting test results..."
    ssh_cmd "cd $REMOTE_DIR/openshift-dpf && tar czf test-results.tar.gz test-results/" || true
    scp -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P "${SSH_PORT:-22}" \
        ${SSH_KEY:+-i "$SSH_KEY"} \
        "${SSH_USER:-root}@$SSH_HOST:$REMOTE_DIR/openshift-dpf/test-results.tar.gz" \
        "$RESULTS_DIR/" || true
    
    log GREEN "Validation tests completed"
    return 0
}

# Generate final report
generate_report() {
    log BLUE "Generating final report..."
    
    cat > "$RESULTS_DIR/final-report.md" << EOF
# DPF CI Test Report

**Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
**DPF Version**: $DPF_VERSION
**Test Mode**: $MODE

## Test Results Summary

### Phase 1: Quick Tests
- Version Detection: ✅ Completed
- Version Comparison: $([ -f "$RESULTS_DIR/version-comparison.md" ] && echo "✅ Completed" || echo "⏭️ Skipped")
- Manifest Validation: $([ -f "$RESULTS_DIR/manifest-updates.md" ] && echo "✅ Completed" || echo "❌ Failed")
- Documentation Analysis: $([ -f "$RESULTS_DIR/rdg-analysis.md" ] && echo "✅ Completed" || echo "⚠️ Partial")

### Phase 2: Hardware Deployment
- Remote Deployment: $([ -f "$RESULTS_DIR/deployment-info.json" ] && echo "✅ Initiated" || echo "⏭️ Skipped")
- CSR Monitoring: $([ -f "$RESULTS_DIR/deployment-info.json" ] && echo "✅ Active" || echo "⏭️ N/A")

### Phase 3: Validation Tests
- API Compatibility: $(grep -q "PASSED" "$RESULTS_DIR/api-compatibility.log" 2>/dev/null && echo "✅ Passed" || echo "❌ Failed/Pending")
- Service Validation: $(grep -q "PASSED" "$RESULTS_DIR/service-validation.log" 2>/dev/null && echo "✅ Passed" || echo "⚠️ Issues/Pending")

## Artifacts

All test results are saved in: $RESULTS_DIR

### Key Files:
$(ls -la "$RESULTS_DIR" | grep -E '\.(md|log|json)$' | awk '{print "- " $9}')

## Next Steps

$(if [ -f "$RESULTS_DIR/deployment-info.json" ]; then
    echo "1. Add worker nodes with DPUs to the deployed cluster"
    echo "2. Monitor deployment: $RESULTS_DIR/monitor-deployment.sh"
    echo "3. Check CSR approvals are working"
    echo "4. Validate DPU services are running"
else
    echo "1. Configure SSH access for hardware testing"
    echo "2. Re-run with hardware tests enabled"
fi)

EOF
    
    log GREEN "Report generated: $RESULTS_DIR/final-report.md"
}

# Main execution
main() {
    log GREEN "Starting DPF CI Test Orchestrator"
    log GREEN "Mode: $MODE"
    log GREEN "Version: ${DPF_VERSION:-auto-detect}"
    
    case "$MODE" in
        quick)
            run_quick_tests || {
                log RED "Quick tests failed"
                exit 1
            }
            ;;
        hardware-only)
            if [ -z "$DPF_VERSION" ]; then
                log RED "DPF version required for hardware-only mode"
                exit 1
            fi
            run_hardware_tests || {
                log RED "Hardware tests failed"
                exit 1
            }
            
            # Wait a bit for deployment to stabilize
            log YELLOW "Waiting 5 minutes for deployment to stabilize..."
            sleep 300
            
            run_validation_tests || {
                log YELLOW "Validation tests had issues"
            }
            ;;
        full|*)
            # Run all phases
            run_quick_tests || {
                log YELLOW "Quick tests had issues, continuing..."
            }
            
            if [ -n "${SSH_HOST:-}" ]; then
                run_hardware_tests || {
                    log RED "Hardware deployment failed"
                    generate_report
                    exit 1
                }
                
                log YELLOW "Hardware deployment initiated"
                log YELLOW "Run validation tests later with: $0 validate $DPF_VERSION"
            else
                log YELLOW "SSH_HOST not set, skipping hardware tests"
                log YELLOW "Set SSH_HOST, SSH_USER, and SSH_KEY to enable hardware testing"
            fi
            ;;
        validate)
            # Just run validation on existing deployment
            run_validation_tests || {
                log RED "Validation tests failed"
                exit 1
            }
            ;;
    esac
    
    generate_report
    
    log GREEN "Test orchestration completed!"
    log GREEN "Results saved to: $RESULTS_DIR"
    
    # Display report
    echo ""
    cat "$RESULTS_DIR/final-report.md"
}

# Show usage
if [ "$MODE" = "help" ] || [ "$MODE" = "--help" ] || [ "$MODE" = "-h" ]; then
    cat << EOF
Usage: $0 [mode] [dpf-version]

Modes:
  quick         - Run only local comparison tests (default)
  full          - Run all tests including hardware deployment
  hardware-only - Skip local tests, deploy directly to hardware
  validate      - Run validation tests on existing deployment
  help          - Show this help message

Environment Variables:
  SSH_HOST      - Remote host for hardware deployment
  SSH_USER      - SSH username (default: root)
  SSH_PORT      - SSH port (default: 22)
  SSH_KEY       - Path to SSH private key

Examples:
  $0 quick v25.4.0              # Quick local tests only
  $0 full                       # Full test with auto-detected version
  $0 hardware-only v25.4.0      # Deploy specific version to hardware
  $0 validate v25.4.0           # Validate existing deployment

EOF
    exit 0
fi

# Run main
main