#!/bin/bash

# Configuration
INSTANCE_NAME=$1  # Pass the instance name as an argument (e.g., wordpress-cms-staging or wordpress-cms-production)
BACKUP_KEY=$2     # The backup file key in S3 (e.g., wordpress-cms-staging/wordpress-cms-staging-backup-20250413120000.tar.gz)
BUCKET_NAME=$(terraform output -raw backup_bucket_name)
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

# Show available backups if no backup key is provided
if [ -z "$BACKUP_KEY" ]; then
  echo -e "${YELLOW}No backup specified. Listing available backups for ${INSTANCE_NAME}:${NC}"
  aws lightsail get-bucket-objects \
    --bucket-name $BUCKET_NAME \
    --query "objects[?starts_with(path, '${INSTANCE_NAME}/')].{Path:path,Size:size,LastModified:createdAt}" \
    --output table

  echo -e "${YELLOW}To restore a backup, run:${NC}"
  echo -e "${YELLOW}$0 ${INSTANCE_NAME} BACKUP_KEY${NC}"
  exit 0
fi

echo -e "${YELLOW}Starting restore of WordPress instance: ${INSTANCE_NAME} from backup: ${BACKUP_KEY}${NC}"

# 1. Download the backup from Lightsail bucket
echo "Downloading backup from Lightsail bucket..."
BACKUP_FILENAME=$(basename "$BACKUP_KEY")
TEMP_DIR="/tmp/wp-restore-$(date +%s)"
mkdir -p $TEMP_DIR

aws lightsail get-bucket-object \
  --bucket-name $BUCKET_NAME \
  --key "$BACKUP_KEY" \
  --path "$TEMP_DIR/$BACKUP_FILENAME"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to download backup from Lightsail bucket. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Backup downloaded successfully.${NC}"

# 2. Extract the backup
echo "Extracting backup..."
tar -xzf "$TEMP_DIR/$BACKUP_FILENAME" -C $TEMP_DIR
BACKUP_DIR=$(find $TEMP_DIR -type d -name "$INSTANCE_NAME-backup-*" | head -n 1)

if [ -z "$BACKUP_DIR" ]; then
  echo -e "${RED}Failed to find backup directory in the archive. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Backup extracted successfully.${NC}"

# 3. Upload the backup files to the instance
echo "Uploading backup files to instance..."
scp -i $SSH_KEY "$BACKUP_DIR/wordpress_db_backup.sql" "$BACKUP_DIR/wp-content-backup.tar.gz" $SSH_USER@$INSTANCE_IP:/tmp/

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to upload backup files to instance. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Backup files uploaded successfully.${NC}"

# 4. Create a backup of the current state before restoring (safety measure)
echo "Creating a backup of the current state before restoring..."
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo /opt/bitnami/wp-cli/bin/wp db export /tmp/pre_restore_backup.sql --path=/opt/bitnami/wordpress && \
  sudo tar -czf /tmp/pre_restore_wp_content.tar.gz -C /opt/bitnami/wordpress wp-content"

# 5. Restore the database
echo "Restoring database..."
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo /opt/bitnami/wp-cli/bin/wp db import /tmp/wordpress_db_backup.sql --path=/opt/bitnami/wordpress"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to restore database. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Database restored successfully.${NC}"

# 6. Restore wp-content directory
echo "Restoring WordPress files..."
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo rm -rf /opt/bitnami/wordpress/wp-content.bak && \
  sudo mv /opt/bitnami/wordpress/wp-content /opt/bitnami/wordpress/wp-content.bak && \
  sudo mkdir -p /opt/bitnami/wordpress/wp-content && \
  sudo tar -xzf /tmp/wp-content-backup.tar.gz -C /opt/bitnami/wordpress && \
  sudo chown -R bitnami:daemon /opt/bitnami/wordpress/wp-content"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to restore WordPress files. Attempting to rollback...${NC}"
  ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo rm -rf /opt/bitnami/wordpress/wp-content && \
    sudo mv /opt/bitnami/wordpress/wp-content.bak /opt/bitnami/wordpress/wp-content && \
    sudo /opt/bitnami/wp-cli/bin/wp db import /tmp/pre_restore_backup.sql --path=/opt/bitnami/wordpress"
  exit 1
fi
echo -e "${GREEN}WordPress files restored successfully.${NC}"

# 7. Flush the WordPress cache
echo "Flushing WordPress cache..."
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo /opt/bitnami/wp-cli/bin/wp cache flush --path=/opt/bitnami/wordpress"

# 8. Restart services
echo "Restarting services..."
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo /opt/bitnami/ctlscript.sh restart apache && \
  sudo /opt/bitnami/ctlscript.sh restart php-fpm && \
  sudo /opt/bitnami/ctlscript.sh restart mysql"

# 9. Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf $TEMP_DIR
ssh -i $SSH_KEY $SSH_USER@$INSTANCE_IP "sudo rm -f /tmp/wordpress_db_backup.sql /tmp/wp-content-backup.tar.gz"

echo -e "${GREEN}Restore completed successfully!${NC}"
echo "WordPress instance ${INSTANCE_NAME} has been restored from backup: ${BACKUP_KEY}"
echo "You can access the WordPress site at: http://$INSTANCE_IP"