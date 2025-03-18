#!/bin/bash

# Script to download and extract the latest WordPress

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if WordPress directory already exists
if [ -d "wordpress" ]; then
    echo -e "${RED}Error: WordPress directory already exists. Please remove or rename it before proceeding.${NC}"
    exit 1
fi

echo "Downloading the latest WordPress..."

# Download the latest WordPress
if ! wget -q https://wordpress.org/latest.tar.gz; then
    echo -e "${RED}Error: Failed to download WordPress.${NC}"
    exit 1
fi

echo "Extracting WordPress..."

# Extract the downloaded file
if ! tar -xzf latest.tar.gz; then
    echo -e "${RED}Error: Failed to extract WordPress.${NC}"
    rm latest.tar.gz
    exit 1
fi

# Clean up the downloaded tar file
rm latest.tar.gz

echo -e "${GREEN}WordPress has been successfully downloaded and extracted.${NC}"
echo "WordPress files are in the 'wordpress' directory."

exit 0