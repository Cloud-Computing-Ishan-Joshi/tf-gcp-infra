variable "project_id" {}

variable "region" {}

# variable "credentials" {}

variable "zone" {}

variable "cidr1" {}
variable "cidr2" {}

variable "route_name" {}

variable "route_dest_range" {}

variable "vm_instance_name" {}

variable "machine_type" {}

variable "custom_image_name" {}

variable "credentials" {}

variable "routing_mode" {
  default = "REGIONAL"
}

variable "image_size" {
  default = "100"
}

variable "image_type" {
  default = "pd-standard"
}

variable "firewall_deny" {
  default = ["22"]
}

variable "firewall_allow" {
  default = ["3000"]
}