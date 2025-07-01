# DPF CI System

This directory contains the continuous integration (CI) system for automatically testing new NVIDIA DPF (Data Processing Framework) versions on OpenShift.

## Overview

The CI system monitors NVIDIA's DOCA Platform releases and automatically:
1. Detects new DPF versions
2. Compares changes between versions
3. Updates manifests for compatibility
4. Deploys test clusters with new versions
5. Runs validation tests
6. Reports results

## Directory Structure

```
ci/
├── config/               # Configuration files
│   └── versions.yaml    # Version tracking and compatibility matrix
├── scripts/             # Core CI scripts
│   ├── version-detector.sh    # Detects new DPF releases
│   └── version-compare.py     # Compares versions for changes
├── tests/               # Test suites
│   ├── api-compatibility-test.sh  # API version validation
│   └── service-validation.sh      # Service deployment tests
├── update/              # Version update tools
│   └── version-updater.py        # Updates manifests to new versions
├── pipelines/           # CI pipeline definitions
├── docs/                # Documentation parsing tools
└── templates/           # Templates for generated files
```

## GitHub Actions Workflows

### 1. DPF Version Monitor (`.github/workflows/dpf-version-monitor.yml`)
- **Schedule**: Daily at 2 AM UTC
- **Purpose**: Checks for new DPF releases
- **Actions**:
  - Detects new versions from NVIDIA/doca-platform
  - Compares with tracked versions
  - Triggers testing for new versions
  - Creates GitHub issues for updates

### 2. DPF Version Test (`.github/workflows/dpf-version-test.yml`)
- **Trigger**: Manual or automated from version monitor
- **Purpose**: Tests new DPF version on OpenShift
- **Actions**:
  - Updates manifests to new version
  - Deploys OpenShift cluster
  - Installs DPF with new version
  - Runs validation tests
  - Reports results

## Usage

### Manual Version Check

```bash
# Check for new versions
./ci/scripts/version-detector.sh detect

# Check if specific version is tested
./ci/scripts/version-detector.sh check v25.4.0

# Get current tracked version
./ci/scripts/version-detector.sh current
```

### Version Comparison

```bash
# Compare two versions
python3 ci/scripts/version-compare.py --old-version v25.1.1 --new-version v25.4.0

# Generate comparison report
python3 ci/scripts/version-compare.py --old-version v25.1.1 --new-version v25.4.0 --output report.md
```

### Update Manifests

```bash
# Update to new version
python3 ci/update/version-updater.py v25.4.0

# Update specific components
python3 ci/update/version-updater.py v25.4.0 --components ovn-kubernetes flannel

# Dry run to see changes
python3 ci/update/version-updater.py v25.4.0 --dry-run
```

### Run Tests Locally

```bash
# Set up environment
export KUBECONFIG=/path/to/kubeconfig

# Run API compatibility tests
./ci/tests/api-compatibility-test.sh v25.4.0

# Run service validation
./ci/tests/service-validation.sh
```

## Configuration

### versions.yaml

The main configuration file tracks:
- Current and tested DPF versions
- Helm chart versions
- API versions
- OpenShift compatibility matrix
- Version-sensitive files

Example:
```yaml
dpf_versions:
  current: v25.4.0
  tested:
    - v25.4.0
    - v25.1.1
    - v25.1.0
```

### Environment Variables

- `GITHUB_TOKEN`: GitHub API token for higher rate limits
- `OPENSHIFT_PULL_SECRET`: Pull secret for OpenShift installation
- `SLACK_WEBHOOK`: Webhook URL for Slack notifications

## Test Suites

### API Compatibility Tests
- Validates CRD existence
- Checks API version compatibility
- Tests resource creation
- Validates schema requirements

### Service Validation Tests
- Checks operator deployment
- Validates service templates
- Tests DPU deployments
- Verifies infrastructure requirements

## Extending the CI

### Adding New Tests

1. Create test script in `ci/tests/`
2. Follow naming convention: `*-test.sh`
3. Use consistent logging and exit codes
4. Add to workflow in `.github/workflows/dpf-version-test.yml`

### Adding Version Checks

1. Update `version_sensitive_files` in `versions.yaml`
2. Add parsing logic to `version-compare.py`
3. Update `version-updater.py` for new patterns

### Customizing Notifications

1. Update GitHub issue templates in workflows
2. Add Slack webhook configuration
3. Customize report generation

## Troubleshooting

### Common Issues

1. **Version detection fails**
   - Check GitHub API rate limits
   - Verify GITHUB_TOKEN is set
   - Check network connectivity

2. **Test cluster fails to deploy**
   - Verify OpenShift pull secret
   - Check resource availability
   - Review cluster logs

3. **Version updates fail**
   - Ensure manifests follow expected structure
   - Check YAML syntax
   - Verify file permissions

### Debugging

```bash
# Enable debug output
export DEBUG=1

# Check CI logs
cat test-results/summary.md

# View operator logs
oc logs -n dpf-operator-system -l control-plane=controller-manager
```

## Contributing

1. Test changes locally first
2. Update documentation
3. Add tests for new features
4. Follow existing patterns
5. Submit PR with clear description

## Future Enhancements

- [ ] Add performance benchmarking
- [ ] Integrate RDG documentation parsing
- [ ] Add upgrade testing (not just fresh installs)
- [ ] Implement automated rollback on failures
- [ ] Add multi-cluster parallel testing
- [ ] Integrate with AI for change analysis