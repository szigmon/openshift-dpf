#!/bin/bash

# Exit on error
set -e

# Function to load environment variables from .env file
load_env() {
    local env_file=".env"
    
    # Check if .env file exists
    if [ ! -f "$env_file" ]; then
        echo "Error: .env file not found"
        exit 1
    }

    # Load environment variables from .env file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue
        
        # Remove any quotes from the value
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        
        # Export the variable
        export "$key=$value"
    done < "$env_file"
}

# Load environment variables
load_env 