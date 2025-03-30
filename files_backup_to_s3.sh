#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
  # Use source to avoid issues with readonly variables
  source .env
else
  echo "Error: .env file not found!"
  exit 1
fi

# Check if S3 credentials are provided
if [ -z "$S3_BACKUP_STORAGE_ENDPOINT" ] || [ -z "$S3_BACKUP_STORAGE_BUCKET" ] || [ -z "$S3_BACKUP_STORAGE_ACCESS_KEY" ] || [ -z "$S3_BACKUP_STORAGE_SECRET_KEY" ]; then
  echo "Error: S3 credentials are incomplete in .env file!"
  exit 1
fi

# Verify container name is properly set
if [ -z "$CONTAINER_NAME" ]; then
  echo "Error: CONTAINER_NAME is not set in .env file!"
  exit 1
fi

# Setup date structure and filenames
YEAR=$(date +"%Y")
MONTH=$(date +"%m")
DAY=$(date +"%d")
HOUR=$(date +"%H")
MINUTES=$(date +"%M")
BACKUP_FILENAME="${CONTAINER_NAME}_${HOUR}_${MINUTES}.tar.bz2"
BACKUP_PATH="/tmp/${BACKUP_FILENAME}"
S3_PATH="backups/files/${YEAR}/${MONTH}/${DAY}/${BACKUP_FILENAME}"

echo "Creating backup of current directories for ${CONTAINER_NAME}..."

# Define directories to exclude from backup
EXCLUDE_DIRS=(
  ".git"
  "node_modules"
  "vendor"
  "storage/logs"
  "storage/app/public"
  ".idea"
  ".vscode"
  "tmp"
  "cache"
)

# Build exclude parameters
EXCLUDE_PARAMS=""
for dir in "${EXCLUDE_DIRS[@]}"; do
  EXCLUDE_PARAMS="${EXCLUDE_PARAMS} --exclude='${dir}'"
done

# Create tar.bz2 archive with maximum compression
# Using eval to properly process the exclude parameters
eval "tar ${EXCLUDE_PARAMS} -cjf \"${BACKUP_PATH}\" --exclude=\"${BACKUP_PATH}\" ."

# Check if tar was successful
if [ $? -ne 0 ]; then
  echo "Error: Directory backup failed!"
  rm -f "${BACKUP_PATH}"  # Clean up any partial file
  exit 1
fi

# Check file size to ensure it's not empty
BACKUP_FILE_SIZE=$(stat -c%s "${BACKUP_PATH}")
if [ "$BACKUP_FILE_SIZE" -lt 100 ]; then  # Minimum expected size
  echo "Error: Backup archive is suspiciously small (${BACKUP_FILE_SIZE} bytes). Aborting."
  rm -f "${BACKUP_PATH}"
  exit 1
fi

echo "Backup successfully created and saved to ${BACKUP_PATH}"
echo "Backup file size: $(du -h ${BACKUP_PATH} | cut -f1)"

# Install AWS CLI if not installed
if ! command -v aws &> /dev/null; then
  echo "AWS CLI not found. Installing..."
  pip install awscli
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install AWS CLI. Please install it manually."
    exit 1
  fi
fi

# Configure S3 settings for MinIO
export AWS_ACCESS_KEY_ID="${S3_BACKUP_STORAGE_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${S3_BACKUP_STORAGE_SECRET_KEY}"
export AWS_DEFAULT_REGION="us-east-1" # This can be any value for MinIO

echo "Uploading backup to MinIO S3 at path ${S3_PATH}..."

# Upload to MinIO S3
aws --endpoint-url="${S3_BACKUP_STORAGE_ENDPOINT}" s3 cp "${BACKUP_PATH}" "s3://${S3_BACKUP_STORAGE_BUCKET}/${S3_PATH}"

# Check if upload was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to upload backup to MinIO S3!"
  echo "The backup file is still available at ${BACKUP_PATH}"
  exit 1
fi

echo "Backup successfully uploaded to MinIO S3."
echo "S3 path: s3://${S3_BACKUP_STORAGE_BUCKET}/${S3_PATH}"

# Clean up temporary backup file
rm -f "${BACKUP_PATH}"
echo "Temporary backup file removed."