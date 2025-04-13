# WordPress Headless CMS on AWS Lightsail

This project provides a complete infrastructure setup for deploying a WordPress headless CMS on AWS Lightsail with separate staging and production environments. It includes Terraform configurations, automation scripts, and GitHub Actions workflows to create a professional DevOps pipeline.

## Features

- **Staging and Production Environments**: Separate WordPress instances for development and live content
- **Infrastructure as Code**: AWS resources defined with Terraform for consistent, repeatable deployments
- **Automated Backups**: Regular backups to Lightsail object storage with retention policies
- **Promotion Workflow**: Simple, safe promotion from staging to production
- **Version Control**: Git tagging for each production release
- **CI/CD Pipeline**: GitHub Actions workflows for automated testing and deployment
- **Headless CMS Configuration**: WordPress configured as a REST API backend for frontend applications

## Prerequisites

- AWS account with proper permissions
- AWS CLI installed and configured
- Terraform installed (v1.0.0+)
- Git
- GitHub account
- SSH key pair for accessing Lightsail instances

## Project Structure

```
wordpress-headless-cms/
├── terraform/
│   ├── main.tf             # Infrastructure definition
│   ├── variables.tf        # Terraform variables definition
│   └── terraform.tfvars    # Values for variables
├── scripts/
│   ├── backup-wordpress.sh       # Script to backup WordPress
│   ├── restore-wordpress.sh      # Script to restore WordPress
│   └── promote-wordpress.sh      # Script to promote staging to production
├── .github/
│   └── workflows/
│       └── wordpress-pipeline.yml  # GitHub Actions workflow
├── docs/
│   ├── setup-guide.md         # Setup documentation
│   └── wordpress-headless.md  # WordPress headless configuration guide
└── README.md                  # This file
```

## Getting Started

### Initial Setup

1. **Clone the repository**:
   ```
   git clone https://github.com/yourusername/wordpress-headless-cms.git
   cd wordpress-headless-cms
   ```

2. **Configure AWS credentials**:
   ```
   aws configure
   ```

3. **Update Terraform variables** (if needed):
   Edit `terraform/terraform.tfvars` to customize:
   - AWS region
   - Project name
   - Instance sizes

### Deploy Infrastructure

1. **Initialize Terraform**:
   ```
   cd terraform
   terraform init
   ```

2. **Deploy infrastructure**:
   ```
   terraform apply
   ```

3. **Note the outputs**:
   ```
   terraform output
   ```
   Save the IP addresses and bucket name for future reference.

### Access WordPress Instances

**Staging**:
- WordPress Site: `http://<staging_public_ip>`
- Admin Panel: `http://<staging_public_ip>/wp-admin`
- Default Username: `user`
- Get Password: 
  ```
  ssh -i ~/.ssh/your_key.pem bitnami@<staging_public_ip> "cat /home/bitnami/bitnami_application_password"
  ```

**Production**:
- WordPress Site: `http://<production_public_ip>`
- Admin Panel: `http://<production_public_ip>/wp-admin`
- Default Username: `user`
- Get Password (same command as staging, but with production IP)

### Configure WordPress as Headless CMS

1. Log in to WordPress admin for both instances

2. **Configure permalinks**:
   - Go to Settings > Permalinks
   - Select "Post name" option
   - Save changes

3. **Install required plugins**:
   - Custom Post Type UI
   - Advanced Custom Fields
   - ACF to REST API (if needed)

4. **Test the REST API**:
   ```
   curl http://<instance_ip>/wp-json/wp/v2/posts
   ```

## Managing Your WordPress Instances

### Backing Up WordPress

Create a backup of either instance:
```
cd scripts
chmod +x backup-wordpress.sh
./backup-wordpress.sh wordpress-cms-staging
# or
./backup-wordpress.sh wordpress-cms-production
```

The backup will be stored in the Lightsail bucket.

### Restoring from Backup

1. **List available backups**:
   ```
   cd scripts
   chmod +x restore-wordpress.sh
   ./restore-wordpress.sh wordpress-cms-staging
   ```

2. **Restore a specific backup**:
   ```
   ./restore-wordpress.sh wordpress-cms-staging wordpress-cms-staging/wordpress-cms-staging-backup-20250413120000.tar.gz
   ```

### Promoting from Staging to Production

After testing changes in staging, promote to production:
```
cd scripts
chmod +x promote-wordpress.sh
./promote-wordpress.sh
```

This script:
- Creates a backup of production (for safety)
- Exports the database from staging
- Transfers wp-content from staging to production
- Updates URLs and settings
- Tags the repository with the version

## Using GitHub Actions

This project includes GitHub Actions workflows for:
- Daily backups
- Automated deployments to staging
- Controlled promotions to production

### Required GitHub Secrets

Set these secrets in your GitHub repository:
- `AWS_ACCESS_KEY_ID`: Your AWS access key
- `AWS_SECRET_ACCESS_KEY`: Your AWS secret key
- `AWS_REGION`: Your AWS region (e.g., ap-south-1)
- `SSH_PRIVATE_KEY`: Your SSH private key for accessing instances
- `TF_API_TOKEN`: Terraform Cloud API token (if using Terraform Cloud)

### Triggering Workflows

- **Automatic**: Push to main branch to deploy to staging
- **Manual**: Go to Actions tab > "WordPress Headless CMS Pipeline" > "Run workflow" > select "true" for "Deploy to production" to promote to production
- **Scheduled**: Daily backups run automatically at 2 AM UTC

## Destroying Infrastructure

When you're done with the project or want to clean up resources:

```
cd terraform
terraform destroy
```

## Troubleshooting

### SSH Connection Issues
- Verify your SSH key has proper permissions: `chmod 600 ~/.ssh/your_key.pem`
- Check if the instance is running: `aws lightsail get-instances`
- Try adding the host to known_hosts: `ssh-keyscan -H <ip> >> ~/.ssh/known_hosts`

### WordPress REST API Issues
- Verify permalinks are set correctly
- Check your CORS configuration
- Test with basic authentication disabled

### Terraform Issues
- Try running with detailed logs: `TF_LOG=DEBUG terraform apply`
- Verify your AWS credentials have the necessary permissions
- Check if resources already exist in the AWS console

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Commit your changes: `git commit -m 'Add feature'`
4. Push to the branch: `git push origin feature-name`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Terraform](https://www.terraform.io/)
- [AWS Lightsail](https://aws.amazon.com/lightsail/)
- [WordPress](https://wordpress.org/)
- [Bitnami WordPress](https://bitnami.com/stack/wordpress)
- [GitHub Actions](https://github.com/features/actions)