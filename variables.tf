variable "project_id" {}
variable "credentials" {}

# VPC configuration
variable "region" {}

variable "zone" {}

variable "cidr1" {}
variable "cidr2" {}

variable "random_special" {
  default = false
}

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
variable "route_dest_range_load_balancer" {
  type    = list(string) # Change to list
  default = ["130.211.0.0/22", "35.191.0.0/16"]
}

# KMS configuration

variable "purpose_crypto_key" {
  default = "ENCRYPT_DECRYPT"
}

variable "rotation_period_crypto_key" {
  # 30 days
  default = "2592000s"
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

# VM Instance Template
variable "check_interval_sec" {
  default = 60
}

variable "timeout_sec" {
  default = 60
}

variable "healthy_threshold" {
  default = 3
}

variable "unhealthy_threshold" {
  default = 5
}

variable "https_health_check_port" {
  default = 3000
}

variable "https_health_check_request_path" {
  default = "/healthz"
}

# Compute Instance Group
variable "base_instance_name" {
  default = "webapp"
}

variable "target_size" {
  default = 3
}

variable "instance_group_named_port_name" {
  default = "http"
}
variable "named_port" {
  default = 3000
}

variable "initial_delay_sec" {
  default = 300
}

# Manage Autoscaler
variable "max_replicas" {
  default = 3
}

variable "autoscalar_port" {
  default = 3000
}

variable "min_replicas" {
  default = 1
}

variable "cooldown_period" {
  default = 60
}

variable "cpu_utilization_target" {
  default = 0.05
}

# Load Balancer
variable "load_balancing_scheme" {
  default = "EXTERNAL"
}

variable "forwarding_rule_ip_protocol" {
  default = "TCP"
}

variable "forwarding_rule_port_range" {
  default = "443"
}

# Backend Service

variable "backend_service_protocol" {
  default = "HTTP"
}

variable "backend_service_port_name" {
  default = "http"
}

variable "backend_service_balancing_mode" {
  default = "UTILIZATION"
}

variable "backend_service_capacity_scaler" {
  default = 1.0
}

variable "backend_service_max_utilization" {
  default = 0.05
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

# Serverless VPC
variable "cidr_vpc_access_connector" {
  default = "10.8.0.0/28"
}

# PubSub configuration

variable "pubsub_topic_name" {
  default = "verify_email"
}

# Bucket configuration

variable "bucket_service_account_name" {
  default = "bucket-service-account"
}

# Cloud Function configuration

variable "cloud_function_service_account_name" {
  default = "cloud-function-service-account"
}

variable "email_from" {}

variable "mailgun_api_key" {
}

variable "available_memory_cloud_function" {
  default = "256M"
}

variable "ingress_settings_cloud_function" {
  default = "ALLOW_INTERNAL_ONLY"
}

variable "zone_cloud_function" {
  default = "us-east1"
}

variable "entry_point_cloud_function" {
  default = "verifyEmail"
}

variable "runtime_cloud_function" {
  default = "nodejs20"
}

variable "event_type_cloud_function" {
  default = "google.cloud.pubsub.topic.v1.messagePublished"
}

variable "retry_policy_cloud_function" {
  default = "RETRY_POLICY_RETRY"
}

variable "webapp_url" {
  default = "https://ishanjoshicloud.me/v1/user/self"
}

variable "packer_image_service_account_email" {
  default = "ubuntu-vm-service-image@dev-1-415017.iam.gserviceaccount.com"
} 