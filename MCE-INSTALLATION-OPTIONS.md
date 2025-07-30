# MCE Installation Options for HyperShift

Due to the MCE bundle unpacking timeout issue, we have created several approaches to install MCE with HyperShift support:

## 1. Check Current Status

```bash
./check-hypershift-status.sh
```

This script checks if HyperShift is already available and provides recommendations.

## 2. MCE Installation Approaches

### Option A: Extended Timeout Approach
```bash
./install-mce-with-timeout-fix.sh
```
- Increases OLM bundle unpacking timeout to 20 minutes
- Restarts OLM operators to apply the configuration
- Monitors installation progress with detailed status

### Option B: Pre-pull Bundle Approach
```bash
./install-mce-prepull.sh
```
- Pre-pulls the MCE bundle image to all nodes using a DaemonSet
- Creates ImageContentSourcePolicy for faster pulls
- Reduces the chance of timeout during bundle unpacking

### Option C: Manual CSV Installation
```bash
./install-mce-manual-csv.sh
```
- Bypasses OLM bundle unpacking entirely
- Creates the MCE operator deployment and CSV manually
- Fastest approach but may miss some OLM-managed features

### Option D: Direct HyperShift Installation
```bash
./install-hypershift-direct.sh
```
- Installs HyperShift directly without MCE
- Uses the hypershift CLI tool
- Simplest approach if MCE features are not required

## 3. Migration from Existing Installation

If you have an existing HyperShift installation via CLI:

```bash
./scripts/migrate-to-mce.sh
```

Options:
- `--skip-backup`: Skip backing up existing resources
- `--force`: Skip confirmation prompt

## Troubleshooting

### Bundle Unpacking Timeout
The error "Job was active longer than specified deadline" indicates the MCE bundle is too large to unpack within the default OLM timeout.

Possible causes:
- Slow network connection to registry.redhat.io
- Proxy configuration issues
- Large bundle size for MCE 2.8

### Namespace Stuck in Terminating
If namespaces are stuck:
```bash
./force-delete-namespace.sh <namespace-name>
```

### Verify Installation
After installation, verify with:
```bash
oc get mce -n multicluster-engine
oc get pods -n hypershift
oc get hostedclusters --all-namespaces
```

## Recommendation

1. First run `./check-hypershift-status.sh` to understand current state
2. If HyperShift CRDs exist, try `./install-hypershift-direct.sh`
3. If you need MCE features, try approaches in this order:
   - Option B (pre-pull) - Most reliable
   - Option A (timeout) - If pre-pull fails
   - Option C (manual) - Last resort

## Next Steps

Once MCE or HyperShift is installed, create the HostedCluster:
```bash
make deploy-hosted-cluster
```