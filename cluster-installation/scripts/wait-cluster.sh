#!/bin/bash

# Default values
CLUSTER_NAME=""
TARGET_STATUS=""
MAX_RETRIES=90
SLEEP_TIME=30

function usage() {
    echo "Usage: $0 -c CLUSTER_NAME -s TARGET_STATUS [-r MAX_RETRIES] [-t SLEEP_TIME]"
    echo
    echo "Wait for an OpenShift cluster to reach a specific status"
    echo
    echo "Required arguments:"
    echo "  -c, --cluster     Cluster name"
    echo "  -s, --status      Target status to wait for"
    echo
    echo "Optional arguments:"
    echo "  -r, --retries     Maximum number of retries (default: 90)"
    echo "  -t, --sleep       Sleep time in seconds between retries (default: 60)"
    echo "  -h, --help        Show this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -s|--status)
            TARGET_STATUS="$2"
            shift 2
            ;;
        -r|--retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        -t|--sleep)
            SLEEP_TIME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$CLUSTER_NAME" || -z "$TARGET_STATUS" ]]; then
    echo "Error: Cluster name and target status are required"
    usage
fi

# Main loop
echo "Waiting for cluster $CLUSTER_NAME to reach status: $TARGET_STATUS"
retries=0

while [ $retries -lt $MAX_RETRIES ]; do
    current_status=$(aicli info cluster "$CLUSTER_NAME" -f status -v)
    echo "Current status: $current_status"

    if [ "$current_status" = "$TARGET_STATUS" ]; then
        echo "Cluster $CLUSTER_NAME has reached status: $TARGET_STATUS"
        exit 0
    fi

    echo "Attempt $retries of $MAX_RETRIES. Waiting $SLEEP_TIME seconds..."
    sleep $SLEEP_TIME
    ((retries++))
done

echo "Timeout waiting for cluster to reach status: $TARGET_STATUS"
exit 1