resource "google_compute_firewall" "allow_http" {

  for_each = google_compute_network.vpc
  name     = "allow-http"
  network  = each.value.self_link

  allow {
    protocol = "tcp"
    ports    = var.firewall_allow
  }

  source_ranges = [var.route_dest_range]

  target_tags = ["${each.key}-webapp", "http-server"]
}

resource "google_compute_firewall" "deny_all" {
  for_each = google_compute_network.vpc
  name     = "deny-all"
  network  = each.value.self_link

  deny {
    protocol = "tcp"
    ports    = var.firewall_deny

  }

  deny {
    protocol = "udp"
    ports    = var.firewall_deny
  }

  source_ranges = [var.route_dest_range]

  # depends_on = [google_compute_firewall.allow_http]
  target_tags = ["${each.key}-webapp"]

}

variable "vpcs" {
  description = "List of VPCs"
  type        = list(string)
  default     = ["vpc1"]
}

resource "google_compute_network" "vpc" {
  for_each                        = toset(var.vpcs)
  name                            = each.key
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp" {
  for_each      = google_compute_network.vpc
  name          = "${each.key}-webapp"
  ip_cidr_range = var.cidr1
  network       = each.value.self_link
  region        = var.region
}

resource "google_compute_subnetwork" "db" {
  for_each      = google_compute_network.vpc
  name          = "${each.key}-db"
  ip_cidr_range = var.cidr2
  network       = each.value.self_link
  region        = var.region
}

resource "google_compute_route" "webapp" {
  for_each         = google_compute_network.vpc
  name             = "${each.key}-route"
  dest_range       = var.route_dest_range
  network          = each.value.name
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
  tags             = ["${each.key}-webapp"]
}

# Create a VM instance with custom image
resource "google_compute_instance" "vm_instance_webapp" {
  for_each     = google_compute_network.vpc
  name         = var.vm_instance_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    # Use Custom Image
    initialize_params {
      image = "projects/${var.project_id}/global/images/${var.custom_image_name}"
      size  = var.image_size
      type  = var.image_type
    }
  }

  network_interface {
    # Use custom VPC and Subnet for network interface
    network    = each.value.self_link
    subnetwork = google_compute_subnetwork.webapp[each.key].self_link
    access_config {
      // Ephemeral IP

    }
  }
  tags = ["${each.key}-webapp", "http-server"]
}