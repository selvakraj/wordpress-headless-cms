#!/bin/bash

# Configuration
STAGING_IP=$(terraform output -raw staging_public_ip)
PRODUCTION_IP=$(terraform output -raw production_public_ip)
SSH_KEY="~/.ssh/id_rsa"
SSH_USER="bitnami"  # WordPress Lightsail instances use 'bitnami' user
VERSION=$(date +"%Y%m%d%H%M%S")
BUCKET_NAME=$(terraform output -raw backup_bucket_name)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting WordPress promotion from staging to production (version: $VERSION)${NC}"

# 1. First, take a backup of the production site (for safety)
echo "Taking a backup of production before promotion..."
./backup-wordpress.sh "wordpress-cms-production"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to backup production. Aborting for safety.${NC}"
  exit 1
fi
echo -e "${GREEN}Production backup completed successfully.${NC}"

# 2. Create database export from staging
echo "Exporting WordPress database from staging..."
ssh -i $SSH_KEY $SSH_USER@$STAGING_IP "sudo /opt/bitnami/wp-cli/bin/wp db export /tmp/staging_db_export.sql --path=/opt/bitnami/wordpress"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to export staging database. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Staging database exported successfully.${NC}"

# 3. Package wp-content directory from staging
echo "Packaging wp-content from staging..."
ssh -i $SSH_KEY $SSH_USER@$STAGING_IP "sudo tar -czf /tmp/staging_wp_content.tar.gz -C /opt/bitnami/wordpress wp-content"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to package wp-content from staging. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Staging wp-content packaged successfully.${NC}"

# 4. Create a package of the WordPress settings and configuration
echo "Packaging WordPress configuration from staging..."
ssh -i $SSH_KEY $SSH_USER@$STAGING_IP "sudo cp /opt/bitnami/wordpress/wp-config.php /tmp/staging_wp_config.php && \
  sudo chown bitnami:daemon /tmp/staging_wp_config.php && \
  sudo chmod 644 /tmp/staging_wp_config.php"

# 5. Download files from staging
echo "Downloading WordPress files from staging..."
mkdir -p /tmp/wp-promotion-$VERSION
scp -i $SSH_KEY $SSH_USER@$STAGING_IP:/tmp/staging_db_export.sql /tmp/wp-promotion-$VERSION/
scp -i $SSH_KEY $SSH_USER@$STAGING_IP:/tmp/staging_wp_content.tar.gz /tmp/wp-promotion-$VERSION/
scp -i $SSH_KEY $SSH_USER@$STAGING_IP:/tmp/staging_wp_config.php /tmp/wp-promotion-$VERSION/

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to download WordPress files from staging. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}WordPress files downloaded successfully.${NC}"

# 6. Upload files to production
echo "Uploading WordPress files to production..."
scp -i $SSH_KEY /tmp/wp-promotion-$VERSION/* $SSH_USER@$PRODUCTION_IP:/tmp/

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to upload WordPress files to production. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}WordPress files uploaded to production successfully.${NC}"

# 7. Replace site URLs in the database dump (to handle domain changes)
echo "Updating site URLs in the database dump..."
STAGING_URL=$(ssh -i $SSH_KEY $SSH_USER@$STAGING_IP "sudo /opt/bitnami/wp-cli/bin/wp option get siteurl --path=/opt/bitnami/wordpress")
PRODUCTION_URL=$(ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo /opt/bitnami/wp-cli/bin/wp option get siteurl --path=/opt/bitnami/wordpress")
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sed -i 's|${STAGING_URL}|${PRODUCTION_URL}|g' /tmp/staging_db_export.sql"

# 8. Import the database on production
echo "Importing database to production..."
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo /opt/bitnami/wp-cli/bin/wp db import /tmp/staging_db_export.sql --path=/opt/bitnami/wordpress"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to import database to production. Aborting.${NC}"
  exit 1
fi
echo -e "${GREEN}Database imported to production successfully.${NC}"

# 9. Update site URLs again to be sure
echo "Updating site URL in production WordPress..."
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo /opt/bitnami/wp-cli/bin/wp option update siteurl '${PRODUCTION_URL}' --path=/opt/bitnami/wordpress && \
  sudo /opt/bitnami/wp-cli/bin/wp option update home '${PRODUCTION_URL}' --path=/opt/bitnami/wordpress"

# 10. Extract wp-content to production
echo "Extracting wp-content to production..."
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo rm -rf /opt/bitnami/wordpress/wp-content.bak && \
  sudo mv /opt/bitnami/wordpress/wp-content /opt/bitnami/wordpress/wp-content.bak && \
  sudo mkdir -p /opt/bitnami/wordpress/wp-content && \
  sudo tar -xzf /tmp/staging_wp_content.tar.gz -C /opt/bitnami/wordpress && \
  sudo chown -R bitnami:daemon /opt/bitnami/wordpress/wp-content"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to extract wp-content to production. Attempting to rollback...${NC}"
  ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo rm -rf /opt/bitnami/wordpress/wp-content && \
    sudo mv /opt/bitnami/wordpress/wp-content.bak /opt/bitnami/wordpress/wp-content"
  exit 1
fi
echo -e "${GREEN}wp-content extracted to production successfully.${NC}"

# 11. Update Permalink Structure (important for headless CMS with REST API)
echo "Updating permalink structure for REST API access..."
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo /opt/bitnami/wp-cli/bin/wp rewrite structure '/%year%/%monthnum%/%postname%/' --path=/opt/bitnami/wordpress"

# 12. Flush the WordPress cache
echo "Flushing WordPress cache..."
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo /opt/bitnami/wp-cli/bin/wp cache flush --path=/opt/bitnami/wordpress"

# 13. Restart services
echo "Restarting services..."
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo /opt/bitnami/ctlscript.sh restart apache && \
  sudo /opt/bitnami/ctlscript.sh restart php-fpm && \
  sudo /opt/bitnami/ctlscript.sh restart mysql"

# 14. Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf /tmp/wp-promotion-$VERSION
ssh -i $SSH_KEY $SSH_USER@$STAGING_IP "sudo rm -f /tmp/staging_db_export.sql /tmp/staging_wp_content.tar.gz /tmp/staging_wp_config.php"
ssh -i $SSH_KEY $SSH_USER@$PRODUCTION_IP "sudo rm -f /tmp/staging_db_export.sql /tmp/staging_wp_content.tar.gz /tmp/staging_wp_config.php"

# 15. Tag the repository with the version
echo "Creating Git tag for this release..."
git tag -a "wp-v$VERSION" -m "WordPress production release $VERSION"
git push origin "wp-v$VERSION"

if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Warning: Failed to create and push Git tag. Please do this manually.${NC}"
else
  echo -e "${GREEN}Git tag created and pushed successfully.${NC}"
fi

echo -e "${GREEN}WordPress promotion completed successfully!${NC}"
echo "You can access the production WordPress admin at: http://$PRODUCTION_IP/wp-admin"
echo "WordPress REST API is available at: http://$PRODUCTION_IP/wp-json"