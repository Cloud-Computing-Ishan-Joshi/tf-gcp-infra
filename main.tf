resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

    source_ranges = ["0.0.0.0/0"]

    target_tags = ["webapp"]
}

resource "google_compute_firewall" "deny_all" {
  name    = "deny-all"
  network = "default"

  deny {
    protocol = "tcp"
    ports = ["22"]
  }

  deny {
    protocol = "udp"
    ports = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]

    depends_on = [google_compute_firewall.allow_http]
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
  routing_mode                    = "REGIONAL"
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
  tags             = ["webapp"]
}

# Create a VM instance with custom image
resource "google_compute_instance" "vm_instance_webapp" {
  name         = var.vm_instance_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    # Use Custom Image
    initialize_params {
      image = "projects/${var.project_id}/global/images/${var.custom_image_name}"
    }
  }

  network_interface {
    # Use custom VPC and Subnet for network interface
    network = google_compute_network.vpc[0].name
    access_config {
        // Ephemeral IP

    }
  }
  tags = [ "webapp" ]
}