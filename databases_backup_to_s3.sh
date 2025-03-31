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

# Verify database credentials are properly set
if [ -z "$DB_DATABASE" ] || [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ] || [ -z "$CONTAINER_NAME" ]; then
  echo "Error: Database credentials are incomplete in .env file!"
  echo "DB_DATABASE: $DB_DATABASE"
  echo "DB_USERNAME: $DB_USERNAME"
  echo "CONTAINER_NAME: $CONTAINER_NAME"
  exit 1
fi

# Setup date structure and filenames
YEAR=$(date +"%Y")
MONTH=$(date +"%m")
DAY=$(date +"%d")
HOUR=$(date +"%H")
MINUTES=$(date +"%M")
BACKUP_FILENAME="${DB_DATABASE}_${HOUR}_${MINUTES}.sql"
COMPRESSED_FILENAME="${BACKUP_FILENAME}.bz2"
BACKUP_PATH="/tmp/${COMPRESSED_FILENAME}"
S3_PATH="backups/databases/${YEAR}/${MONTH}/${DAY}/${COMPRESSED_FILENAME}"

echo "Creating backup of database ${DB_DATABASE}..."

# Create a temporary SQL file first
TEMP_SQL_FILE="/tmp/${BACKUP_FILENAME}"

# Create MySQL dump
docker exec ${CONTAINER_NAME}_mysql mysqldump -u"root" -p"${DB_PASSWORD}_root" "${DB_DATABASE}" > "${TEMP_SQL_FILE}"

# Check if mysqldump was successful
if [ $? -ne 0 ] || [ ! -s "${TEMP_SQL_FILE}" ]; then
  echo "Error: Database backup failed! The SQL file is empty or mysqldump returned an error."
  rm -f "${TEMP_SQL_FILE}"  # Clean up empty file
  exit 1
fi

# Check file size to ensure it's not empty
SQL_FILE_SIZE=$(stat -c%s "${TEMP_SQL_FILE}")
if [ "$SQL_FILE_SIZE" -lt 100 ]; then  # Minimum expected size
  echo "Error: Database dump is suspiciously small (${SQL_FILE_SIZE} bytes). Aborting."
  rm -f "${TEMP_SQL_FILE}"
  exit 1
fi

# Compress the SQL file
bzip2 -9 -f "${TEMP_SQL_FILE}"

# Check if compression was successful
if [ $? -ne 0 ] || [ ! -f "${TEMP_SQL_FILE}.bz2" ]; then
  echo "Error: Compression failed!"
  rm -f "${TEMP_SQL_FILE}" "${TEMP_SQL_FILE}.bz2"
  exit 1
fi

# Move to final backup path
mv "${TEMP_SQL_FILE}.bz2" "${BACKUP_PATH}"

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

# Handle backup retention
echo "Managing backup retention..."

# Set default retention if not defined
if [ -z "$DATABASE_BACKUP_RETENTION" ]; then
  DATABASE_BACKUP_RETENTION=10
  echo "DATABASE_BACKUP_RETENTION not set, using default value: 10"
fi

# List all database backups in S3, sorted by date (oldest first)
echo "Listing existing backups..."
BACKUP_LIST=$(aws --endpoint-url="${S3_BACKUP_STORAGE_ENDPOINT}" \
  s3 ls "s3://${S3_BACKUP_STORAGE_BUCKET}/backups/databases/" --recursive | \
  grep '\.sql\.bz2$' | sort)

# Count total backups
BACKUP_COUNT=$(echo "$BACKUP_LIST" | wc -l)
echo "Found $BACKUP_COUNT existing backups"

# Calculate how many backups to delete
DELETE_COUNT=$((BACKUP_COUNT - DATABASE_BACKUP_RETENTION))

if [ $DELETE_COUNT -gt 0 ]; then
  echo "Removing $DELETE_COUNT old backups to maintain retention policy of $DATABASE_BACKUP_RETENTION backups..."
  
  # Get the list of backups to delete (oldest first)
  BACKUPS_TO_DELETE=$(echo "$BACKUP_LIST" | head -n $DELETE_COUNT)
  
  # Delete each old backup
  while read -r BACKUP_LINE; do
    # Extract the S3 path from the listing
    BACKUP_PATH=$(echo "$BACKUP_LINE" | awk '{print $4}')
    echo "Deleting old backup: $BACKUP_PATH"
    
    aws --endpoint-url="${S3_BACKUP_STORAGE_ENDPOINT}" \
      s3 rm "s3://${S3_BACKUP_STORAGE_BUCKET}/$BACKUP_PATH"
      
    if [ $? -ne 0 ]; then
      echo "Warning: Failed to delete backup $BACKUP_PATH"
    fi
  done <<< "$BACKUPS_TO_DELETE"
  
  echo "Completed cleanup of old backups"
else
  echo "No backups need to be deleted (current count: $BACKUP_COUNT, retention: $DATABASE_BACKUP_RETENTION)"
fi
