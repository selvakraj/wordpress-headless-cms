#!/bin/bash

# Configuration
INSTANCE_NAME=$1  # Pass the instance name as an argument (e.g., wordpress-cms-staging or wordpress-cms-production)
BUCKET_NAME=$(terraform output -raw backup_bucket_name)
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_NAME="${INSTANCE_NAME}-backup-${TIMESTAMP}"
SSH_KEY="~/.ssh/id_rsa"
SSH_USER="bitnami"  # WordPress Lightsail instances use 'bitnami' user

# Get instance IP
if [[ $INSTANCE_NAME == *"staging"* ]]; then
  INSTANCE_IP=$(terraform output -raw staging_public_ip)
elif [[ $INSTANCE_NAME == *"production"* ]]; then
  INSTANCE_IP=$(terraform output -raw production_public_ip)
else
  echo "Error: Invalid instance name. Please use the full instance name (e.g., wordpress-cms-staging)"
  exit 1
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting backup of WordPress instance: ${INSTANCE_NAME}${NC}"

# 1. Create a database backup on the instance
echo "Creating database backup on the instance..."
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo /opt/bitnami/wp-cli/bin/wp db export /tmp/wordpress_db_backup.sql --path=/opt/bitnami/wordpress"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to create database backup. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Database backup created successfully.${NC}"

# 2. Create a backup of wp-content directory
echo "Creating backup of WordPress files..."
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo tar -czf /tmp/wp-content-backup.tar.gz -C /opt/bitnami/wordpress wp-content"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to create file backup. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}WordPress files backup created successfully.${NC}"

# 3. Download the backups
echo "Downloading backups from instance..."
mkdir -p /tmp/$BACKUP_NAME
scp -i $SSH_KEY $SSH_USER@$INSTANCE_IP:/tmp/wordpress_db_backup.sql /tmp/$BACKUP_NAME/
scp -i $SSH_KEY $SSH_USER@$INSTANCE_IP:/tmp/wp-content-backup.tar.gz /tmp/$BACKUP_NAME/

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to download backups. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Backups downloaded successfully.${NC}"

# 4. Create metadata file
echo "Creating backup metadata..."
cat > /tmp/$BACKUP_NAME/metadata.json << EOF
{
  "instance": "$INSTANCE_NAME",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "wordpress_version": "$(ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo /opt/bitnami/wp-cli/bin/wp core version --path=/opt/bitnami/wordpress")",
  "backup_type": "full",
  "components": ["database", "wp-content"]
}
EOF

# 5. Create a single archive of all backups
echo "Creating final backup archive..."
tar -czf /tmp/${BACKUP_NAME}.tar.gz -C /tmp $BACKUP_NAME

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to create final backup archive. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Backup archive created successfully.${NC}"

# 6. Upload to Lightsail bucket
echo "Uploading backup to Lightsail bucket: $BUCKET_NAME..."
aws lightsail upload-object \
  --bucket-name $BUCKET_NAME \
  --key "${INSTANCE_NAME}/${BACKUP_NAME}.tar.gz" \
  --body "/tmp/${BACKUP_NAME}.tar.gz" \
  --region $(terraform output -raw aws_region 2>/dev/null || echo "ap-south-1")

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to upload backup to Lightsail bucket. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Backup uploaded to Lightsail bucket successfully.${NC}"

# 7. Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf /tmp/$BACKUP_NAME /tmp/${BACKUP_NAME}.tar.gz
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo rm -f /tmp/wordpress_db_backup.sql /tmp/wp-content-backup.tar.gz"

if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Warning: Failed to clean up some temporary files.${NC}"
else
  echo -e "${GREEN}Temporary files cleaned up successfully.${NC}"
fi

# 8. Create a list of available backups for this instance
echo "Updating backup inventory..."
aws lightsail get-bucket-objects \
  --bucket-name $BUCKET_NAME \
  --region $(terraform output -raw aws_region 2>/dev/null || echo "ap-south-1") \
  --query "objects[?starts_with(path, '$INSTANCE_NAME/')].{Key:path,Size:size,LastModified:createdAt}" \
  --output json > /tmp/backup_inventory.json

aws lightsail upload-object \
  --bucket-name $BUCKET_NAME \
  --key "${INSTANCE_NAME}/backup_inventory.json" \
  --body "/tmp/backup_inventory.json" \
  --region $(terraform output -raw aws_region 2>/dev/null || echo "ap-south-1")

rm -f /tmp/backup_inventory.json

echo -e "${GREEN}Backup completed successfully!${NC}"
echo "Backup name: ${BACKUP_NAME}.tar.gz"
echo "Backup location: s3://${BUCKET_NAME}/${INSTANCE_NAME}/${BACKUP_NAME}.tar.gz"