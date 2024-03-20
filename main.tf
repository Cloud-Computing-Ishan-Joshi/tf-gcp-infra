# Create a VPC with custom subnet

resource "google_project_service" "service_networking" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"
}

variable "vpcs" {
  description = "List of VPCs"
  type        = list(string)
  default     = ["vpc1"]
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "random_id" "db_name_suffix" {
  byte_length = 8
}

resource "google_compute_network" "vpc" {
  for_each                        = toset(var.vpcs)
  name                            = each.key
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = true

  depends_on = [google_project_service.service_networking]
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

# Create a Cloud SQL instance

resource "google_sql_database_instance" "db_instance" {
  for_each = google_compute_network.vpc
  # random instance name
  name                = "${each.key}-db-instance-${random_id.db_name_suffix.hex}"
  region              = var.region
  project             = var.project_id
  database_version    = var.db_version
  deletion_protection = var.deletion_protection_enabled
  depends_on          = [google_service_networking_connection.private_vpc_connection]
  settings {
    tier                        = var.db_tier
    deletion_protection_enabled = var.deletion_protection_enabled
    availability_type           = var.db_availability_type
    disk_type                   = var.db_disk_type
    disk_size                   = var.db_disk_size
    ip_configuration {
      ipv4_enabled    = var.ipv4_enabled
      private_network = google_compute_network.vpc[each.key].self_link
    }
  }
  lifecycle {
    ignore_changes = [
      settings
    ]
  }
}

# Create VPC Peering Connection between VPC and Cloud SQL
resource "google_compute_global_address" "private_ip" {
  for_each      = google_compute_network.vpc
  name          = "${each.key}-private-ip"
  purpose       = var.private_ip_purpose
  ip_version    = var.ip_version
  address_type  = var.address_type
  prefix_length = var.prefix_length
  network       = each.value.self_link
  lifecycle {
    prevent_destroy = false
  }

}

resource "google_service_networking_connection" "private_vpc_connection" {
  for_each                = google_compute_network.vpc
  network                 = each.value.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip[each.key].name]

  depends_on = [
    google_compute_global_address.private_ip
  ]
}


resource "google_sql_database" "db" {
  for_each = google_compute_network.vpc
  name     = var.database_name
  instance = google_sql_database_instance.db_instance[each.key].name
}

resource "google_sql_user" "db_user" {
  for_each = google_compute_network.vpc
  name     = var.db_user_name
  instance = google_sql_database_instance.db_instance[each.key].name
  password = random_password.db_password.result
}

#  Create a Service Account
resource "google_service_account" "service_account" {
  for_each     = google_compute_network.vpc
  account_id   = "ops-agent-service-account-${each.key}"
  display_name = "OPS Agent Service Account for ${each.key}"
}

# Create a Binding for the Service Account for logging (writing and viewing), and monitoring (writing and viewing)
resource "google_project_iam_member" "service_account_binding" {
  for_each = google_compute_network.vpc
  role     = "roles/logging.admin"
  member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
  project  = var.project_id
}

resource "google_project_iam_member" "service_account_binding_monitoring" {
  for_each = google_compute_network.vpc
  role     = "roles/monitoring.metricWriter"
  member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
  project  = var.project_id
}

resource "google_project_iam_member" "service_account_binding_monitoring_view" {
  for_each = google_compute_network.vpc
  role     = "roles/monitoring.viewer"
  member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
  project  = var.project_id
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
  metadata = {
    startup-script = templatefile("startup_script.sh", {
      db_host     = google_sql_database_instance.db_instance[each.key].private_ip_address,
      db_user     = google_sql_user.db_user[each.key].name,
      db_password = google_sql_user.db_user[each.key].password,
      db_name     = google_sql_database.db[each.key].name
      chown_user  = var.chown_user
    })

  }

  service_account {
    email  = google_service_account.service_account[each.key].email
    scopes = var.vm_service_account_scopes
  }

  # depends_on = [ google_sql_database_instance.db_instance[each.key], google_sql_user.db_user[each.key], google_sql_database.db[each.key], google_service_account.service_account[each.key] ]

  tags = ["${each.key}-webapp", "http-server"]
}

# Create a DNS record for the VM instance
resource "google_dns_record_set" "webapp_dns" {
  for_each     = google_compute_network.vpc
  name         = var.dns_name
  type         = var.dns_type
  ttl          = var.dns_ttl
  managed_zone = var.dns_managed_zone
  rrdatas      = [google_compute_instance.vm_instance_webapp[each.key].network_interface[0].access_config[0].nat_ip]
}

# Create a firewall rule

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

  target_tags = ["${each.key}-webapp"]

}

