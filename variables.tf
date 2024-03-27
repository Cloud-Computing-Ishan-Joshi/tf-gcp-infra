variable "project_id" {}
variable "credentials" {}

# VPC configuration
variable "region" {}

variable "zone" {}

variable "cidr1" {}
variable "cidr2" {}

variable "routing_mode" {
  default = "REGIONAL"
}

variable "route_name" {}

variable "route_dest_range" {}

# Network configuration
variable "private_ip_purpose" {
  default = "VPC_PEERING"
}

variable "ip_version" {
  default = "IPV4"
}

variable "address_type" {
  default = "INTERNAL"
}

variable "prefix_length" {
  default = 16
}

variable "prevent_destroy" {
  default = false
}


# VM Instance

variable "vm_instance_name" {}

variable "machine_type" {}

variable "custom_image_name" {}

variable "image_size" {
  default = "100"
}

variable "image_type" {
  default = "pd-standard"
}

variable "vm_service_account_scopes" {
  default = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write", "https://www.googleapis.com/auth/pubsub"]
}

# DNS configuration

variable "dns_name" {}

variable "dns_type" {
  default = "A"
}

variable "dns_ttl" {
  default = 300
}

variable "dns_managed_zone" {}

# Firewall configuration
variable "firewall_deny" {
  default = ["22"]
}

variable "firewall_allow" {
  default = ["3000"]
}

# Database configuration
variable "db_tier" {
  default = "db-f1-micro"
}

variable "db_version" {
  default = "POSTGRES_15"
}

variable "db_disk_size" {
  default = "10"
}

variable "db_disk_type" {
  default = "pd-ssd"
}

variable "db_availability_type" {
  default = "REGIONAL"
}

variable "deletion_protection_enabled" {
  default = false
}

variable "ipv4_enabled" {
  default = false
}

variable "enable_private_path_for_google_cloud_services" {
  default = true
}

variable "database_name" {
  default = "webapp"
}

variable "db_user_name" {
  default   = "webapp"
  sensitive = true
}

variable "chown_user" {
  default = "csye6225"
}


# Cloud Function configuration
variable "email_from" {}

variable "mailgun_api_key" {

}