provider "aws" {
  region = var.aws_region
}

# Staging Lightsail WordPress Instance
resource "aws_lightsail_instance" "staging" {
  name              = "${var.project_name}-staging"
  availability_zone = "${var.aws_region}a"
  blueprint_id      = "wordpress"  # WordPress blueprint
  bundle_id         = var.bundle_id
  tags = {
    Environment = "staging"
  }
}

# Production Lightsail WordPress Instance
resource "aws_lightsail_instance" "production" {
  name              = "${var.project_name}-production"
  availability_zone = "${var.aws_region}a"
  blueprint_id      = "wordpress"  # WordPress blueprint
  bundle_id         = var.bundle_id
  tags = {
    Environment = "production"
  }
}

# Create static IPs for both instances
resource "aws_lightsail_static_ip" "staging_static_ip" {
  name = "${var.project_name}-staging-static-ip"
}

resource "aws_lightsail_static_ip" "production_static_ip" {
  name = "${var.project_name}-production-static-ip"
}

# Attach static IPs to instances
resource "aws_lightsail_static_ip_attachment" "staging_static_ip_attachment" {
  static_ip_name = aws_lightsail_static_ip.staging_static_ip.name
  instance_name  = aws_lightsail_instance.staging.name
}

resource "aws_lightsail_static_ip_attachment" "production_static_ip_attachment" {
  static_ip_name = aws_lightsail_static_ip.production_static_ip.name
  instance_name  = aws_lightsail_instance.production.name
}

# Create Lightsail Bucket for backups
resource "aws_lightsail_bucket" "backups" {
  name      = "${var.project_name}-backups"
  bundle_id = "small_1_0"  # Smallest bucket size
  
  tags = {
    Project = var.project_name
  }
}
# Open necessary ports for WordPress
resource "aws_lightsail_instance_public_ports" "staging_ports" {
  instance_name = aws_lightsail_instance.staging.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }
}

resource "aws_lightsail_instance_public_ports" "production_ports" {
  instance_name = aws_lightsail_instance.production.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }
}

# Output the public IPs of both instances and bucket info
output "staging_public_ip" {
  value = aws_lightsail_static_ip.staging_static_ip.ip_address
}

output "production_public_ip" {
  value = aws_lightsail_static_ip.production_static_ip.ip_address
}

output "backup_bucket_name" {
  value = aws_lightsail_bucket.backups.name
}

output "staging_wordpress_username" {
  value = "user"
  description = "Default WordPress admin username for staging (check instance for password)"
}

output "production_wordpress_username" {
  value = "user"
  description = "Default WordPress admin username for production (check instance for password)"
}