#!/bin/bash

# Version Detection Script for NVIDIA DPF
# This script checks for new DPF releases and compares with tracked versions

set -euo pipefail

# Source directory configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$CI_DIR")"
CONFIG_FILE="${CI_DIR}/config/versions.yaml"

# GitHub API configuration
GITHUB_API="https://api.github.com"
DOCA_REPO="NVIDIA/doca-platform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[${timestamp}] [INFO]${NC} ${message}"
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}] [WARN]${NC} ${message}"
            ;;
        ERROR)
            echo -e "${RED}[${timestamp}] [ERROR]${NC} ${message}"
            ;;
    esac
}

# Function to get current version from config
get_current_version() {
    local current_version=$(yq eval '.dpf_versions.current' "$CONFIG_FILE")
    echo "$current_version"
}

# Function to get tested versions from config
get_tested_versions() {
    yq eval '.dpf_versions.tested[]' "$CONFIG_FILE"
}

# Function to fetch latest releases from GitHub
fetch_latest_releases() {
    local limit=${1:-10}
    local api_url="${GITHUB_API}/repos/${DOCA_REPO}/releases?per_page=${limit}"
    
    log INFO "Fetching latest releases from ${DOCA_REPO}..."
    
    # Check if we have GitHub token for higher rate limits
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$api_url"
    else
        curl -s "$api_url"
    fi
}

# Function to fetch tags from GitHub
fetch_tags() {
    local limit=${1:-20}
    local api_url="${GITHUB_API}/repos/${DOCA_REPO}/tags?per_page=${limit}"
    
    log INFO "Fetching tags from ${DOCA_REPO}..."
    
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$api_url"
    else
        curl -s "$api_url"
    fi
}

# Function to extract version from tag/release name
extract_version() {
    local tag_name=$1
    # Extract version pattern like v25.4.0
    echo "$tag_name" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

# Function to compare versions
# Returns: 0 if equal, 1 if v1 > v2, 2 if v1 < v2
compare_versions() {
    local v1=$1
    local v2=$2
    
    # Remove 'v' prefix if present
    v1=${v1#v}
    v2=${v2#v}
    
    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi
    
    # Compare using sort -V (version sort)
    local sorted=$(echo -e "$v1\n$v2" | sort -V | head -n1)
    
    if [[ "$sorted" == "$v1" ]]; then
        return 2  # v1 < v2
    else
        return 1  # v1 > v2
    fi
}

# Function to check if version is already tested
is_version_tested() {
    local version=$1
    local tested_versions=$(get_tested_versions)
    
    while IFS= read -r tested_version; do
        if [[ "$version" == "$tested_version" ]]; then
            return 0
        fi
    done <<< "$tested_versions"
    
    return 1
}

# Function to detect new versions
detect_new_versions() {
    local current_version=$(get_current_version)
    local new_versions=()
    
    log INFO "Current tracked version: ${current_version}"
    
    # Fetch releases
    local releases=$(fetch_latest_releases 20)
    
    # Parse releases for version tags
    while IFS= read -r tag_name; do
        local version=$(extract_version "$tag_name")
        
        if [ -n "$version" ]; then
            if ! is_version_tested "$version"; then
                compare_versions "$version" "$current_version"
                local cmp_result=$?
                
                if [ $cmp_result -eq 1 ]; then
                    log INFO "Found newer version: ${version}"
                    new_versions+=("$version")
                elif [ $cmp_result -eq 2 ]; then
                    log INFO "Found older untested version: ${version}"
                    new_versions+=("$version")
                fi
            fi
        fi
    done < <(echo "$releases" | jq -r '.[].tag_name')
    
    # Also check tags in case some versions aren't released
    local tags=$(fetch_tags 30)
    
    while IFS= read -r tag_name; do
        local version=$(extract_version "$tag_name")
        
        if [ -n "$version" ]; then
            if ! is_version_tested "$version"; then
                # Check if already in new_versions array
                local found=0
                for v in "${new_versions[@]}"; do
                    if [[ "$v" == "$version" ]]; then
                        found=1
                        break
                    fi
                done
                
                if [ $found -eq 0 ]; then
                    compare_versions "$version" "$current_version"
                    local cmp_result=$?
                    
                    if [ $cmp_result -eq 1 ]; then
                        log INFO "Found newer version in tags: ${version}"
                        new_versions+=("$version")
                    fi
                fi
            fi
        fi
    done < <(echo "$tags" | jq -r '.[].name')
    
    # Sort new versions
    if [ ${#new_versions[@]} -gt 0 ]; then
        log INFO "New versions found: ${new_versions[*]}"
        
        # Sort versions in descending order
        IFS=$'\n' sorted_versions=($(printf '%s\n' "${new_versions[@]}" | sort -rV))
        
        # Return the sorted array
        printf '%s\n' "${sorted_versions[@]}"
    else
        log INFO "No new versions detected"
    fi
}

# Function to get release details
get_release_details() {
    local version=$1
    local api_url="${GITHUB_API}/repos/${DOCA_REPO}/releases/tags/${version}"
    
    log INFO "Fetching release details for ${version}..."
    
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$api_url"
    else
        curl -s "$api_url"
    fi
}

# Function to check branch existence
check_branch_exists() {
    local version=$1
    local branch_name="release-${version}"
    local api_url="${GITHUB_API}/repos/${DOCA_REPO}/branches/${branch_name}"
    
    log INFO "Checking if branch ${branch_name} exists..."
    
    local response
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token ${GITHUB_TOKEN}" "$api_url")
    else
        response=$(curl -s -o /dev/null -w "%{http_code}" "$api_url")
    fi
    
    if [ "$response" -eq 200 ]; then
        log INFO "Branch ${branch_name} exists"
        return 0
    else
        log WARN "Branch ${branch_name} not found"
        return 1
    fi
}

# Main execution
main() {
    local command=${1:-detect}
    
    case $command in
        detect)
            detect_new_versions
            ;;
        check)
            local version=${2:-}
            if [ -z "$version" ]; then
                log ERROR "Version required for check command"
                exit 1
            fi
            
            if is_version_tested "$version"; then
                log INFO "Version ${version} is already tested"
                exit 0
            else
                log INFO "Version ${version} is not tested"
                exit 1
            fi
            ;;
        details)
            local version=${2:-}
            if [ -z "$version" ]; then
                log ERROR "Version required for details command"
                exit 1
            fi
            
            get_release_details "$version"
            ;;
        branch)
            local version=${2:-}
            if [ -z "$version" ]; then
                log ERROR "Version required for branch command"
                exit 1
            fi
            
            check_branch_exists "$version"
            ;;
        current)
            get_current_version
            ;;
        tested)
            get_tested_versions
            ;;
        *)
            log ERROR "Unknown command: $command"
            echo "Usage: $0 {detect|check|details|branch|current|tested} [version]"
            exit 1
            ;;
    esac
}

# Check dependencies
if ! command -v yq &> /dev/null; then
    log ERROR "yq is required but not installed. Please install yq."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log ERROR "jq is required but not installed. Please install jq."
    exit 1
fi

# Run main function
main "$@"