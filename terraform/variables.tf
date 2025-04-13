variable "aws_region" {
  description = "AWS region for Lightsail instances"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name of your project"
  type        = string
  default     = "terraform-webapp"
}

variable "blueprint_id" {
  description = "Lightsail blueprint (OS) to use"
  type        = string
  default     = "amazon_linux_2"
}

variable "bundle_id" {
  description = "Lightsail instance size"
  type        = string
  default     = "nano_2_0"
}