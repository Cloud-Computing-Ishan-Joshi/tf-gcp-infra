# Create a VPC with custom subnet
resource "google_project_service" "service_networking" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"
}

variable "vpcs" {
  description = "List of VPCs"
  type        = list(string)
  default     = ["vpc2"]
}

variable "random_number" {
  description = "Random number"
  type        = number
  default     = 20
}

resource "random_password" "db_password" {
  length  = 16
  special = var.random_special
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

# Create a Custom Key Ring
resource "google_kms_key_ring" "key_ring" {
  for_each = google_compute_network.vpc
  name     = "${each.key}-key-ring${var.key_ring_number}"
  location = var.region
}

# Create a Custom Crypto Key for VM instance
resource "google_kms_crypto_key" "crypto_key_vm" {
  for_each        = google_compute_network.vpc
  name            = "${each.key}-vm-crypto-key"
  purpose         = var.purpose_crypto_key
  key_ring        = google_kms_key_ring.key_ring[each.key].id
  rotation_period = var.rotation_period_crypto_key
  lifecycle {
    create_before_destroy = true
  }
}

# Create a Custom Crypto Key for Cloud SQL
resource "google_kms_crypto_key" "crypto_key_db" {
  for_each = google_compute_network.vpc
  name     = "${each.key}-db-crypto-key"
  purpose  = "ENCRYPT_DECRYPT"
  key_ring = google_kms_key_ring.key_ring[each.key].id
  # key_ring     = "projects/${var.project_id}/locations/${var.region}/keyRings/vpc2-key-ring"
  rotation_period = var.rotation_period_crypto_key
  lifecycle {
    create_before_destroy = true
  }
}

# Create a Custom Crypto Key for Bucket
resource "google_kms_crypto_key" "crypto_key_bucket" {
  for_each        = google_compute_network.vpc
  name            = "${each.key}-bucket-crypto-key"
  purpose         = "ENCRYPT_DECRYPT"
  key_ring        = google_kms_key_ring.key_ring[each.key].id
  rotation_period = var.rotation_period_crypto_key
  lifecycle {
    create_before_destroy = true
  }
}

# Create a Cloud SQL service account for KMS key
resource "google_project_service_identity" "gcp_sa_cloud_sql" {
  provider = google-beta
  project  = var.project_id
  service  = "sqladmin.googleapis.com"
}
resource "google_kms_crypto_key_iam_binding" "crypto_key_db" {
  for_each      = google_compute_network.vpc
  crypto_key_id = google_kms_crypto_key.crypto_key_db[each.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_project_service_identity.gcp_sa_cloud_sql.email}",
  ]
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
  encryption_key_name = google_kms_crypto_key.crypto_key_db[each.key].id
  depends_on          = [google_service_networking_connection.private_vpc_connection, google_kms_crypto_key_iam_binding.crypto_key_db]
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

# Binding Pub/Sub Publisher role to the service account
resource "google_project_iam_member" "service_account_binding_pubsub" {
  for_each = google_compute_network.vpc
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
  project  = var.project_id
}
# Binding KMS CryptoKey Encrypter/Decrypter role to the service account
resource "google_project_iam_member" "service_account_binding_kms" {
  for_each = google_compute_network.vpc
  role     = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
  project  = var.project_id
}

# Permissions for Using Google-managed SSL certificates
# resource "google_project_iam_member" "service_account_binding_ssl" {
#   for_each = google_compute_network.vpc
#   role     = "roles/compute.sslCertificates.*"
#   member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
#   project  = var.project_id

# }

# resource "google_project_iam_member" "service_account_binding_compute" {
#   for_each = google_compute_network.vpc
#   role     = "roles/compute.targetHttpsProxies.*"
#   member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
#   project  = var.project_id
# }

# resource "google_project_iam_member" "service_account_binding_compute2" {
#   for_each = google_compute_network.vpc
#   role     = "roles/compute.targetSslProxies.*"
#   member   = "serviceAccount:${google_service_account.service_account[each.key].email}"
#   project  = var.project_id
# }

# Create a VM instance with custom image
# resource "google_compute_instance_tem" "vm_instance_webapp" {
#   for_each     = google_compute_network.vpc
#   name         = var.vm_instance_name
#   machine_type = var.machine_type
#   zone         = var.zone

#   boot_disk {
#     # Use Custom Image
#     initialize_params {
#       image = "projects/${var.project_id}/global/images/${var.custom_image_name}"
#       size  = var.image_size
#       type  = var.image_type
#     }
#   }

#   network_interface {
#     # Use custom VPC and Subnet for network interface
#     network    = each.value.self_link
#     subnetwork = google_compute_subnetwork.webapp[each.key].self_link
#     access_config {
#       // Ephemeral IP

#     }
#   }
#   metadata = {
#     startup-script = templatefile("startup_script.sh", {
#       db_host     = google_sql_database_instance.db_instance[each.key].private_ip_address,
#       db_user     = google_sql_user.db_user[each.key].name,
#       db_password = google_sql_user.db_user[each.key].password,
#       db_name     = google_sql_database.db[each.key].name,
#       chown_user  = var.chown_user,
#       project_id  = var.project_id,
#       topic_name  = google_pubsub_topic.verify_email[each.key].name
#     })

#   }

#   service_account {
#     email  = google_service_account.service_account[each.key].email
#     scopes = var.vm_service_account_scopes
#   }

#   tags = ["${each.key}-webapp", "http-server"]
# }

data "google_compute_default_service_account" "default" {
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "compute_engine_kms_binding" {
  for_each      = google_compute_network.vpc
  crypto_key_id = google_kms_crypto_key.crypto_key_vm[each.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_kms_crypto_key_iam_binding" "binding_vm_disk_key" {
  for_each      = google_compute_network.vpc
  crypto_key_id = google_kms_crypto_key.crypto_key_vm[each.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members       = ["serviceAccount:service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"]
}

# Create a VM Instance template with custom image
resource "google_compute_region_instance_template" "webapp_template" {
  for_each     = google_compute_network.vpc
  name         = "${each.key}-webapp-template"
  machine_type = var.machine_type

  disk {
    source_image = "projects/${var.project_id}/global/images/${var.custom_image_name}"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.image_size
    disk_type    = var.image_type
    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.crypto_key_vm[each.key].id
    }
  }

  network_interface {
    network    = each.value.self_link
    subnetwork = google_compute_subnetwork.webapp[each.key].self_link
    access_config {
      // Ephemeral IP
    }
  }

  metadata_startup_script = templatefile("startup_script.sh", {
    db_host     = google_sql_database_instance.db_instance[each.key].private_ip_address,
    db_user     = google_sql_user.db_user[each.key].name,
    db_password = google_sql_user.db_user[each.key].password,
    db_name     = google_sql_database.db[each.key].name,
    chown_user  = var.chown_user,
    project_id  = var.project_id,
    topic_name  = google_pubsub_topic.verify_email[each.key].name
  })

  service_account {
    email  = google_service_account.service_account[each.key].email
    scopes = var.vm_service_account_scopes
  }

  tags = ["${each.key}-webapp", "http-server"]
}

# Create a Compute Health Check
resource "google_compute_health_check" "webapp_health_check" {
  for_each            = google_compute_network.vpc
  name                = "${each.key}-webapp-health-check"
  check_interval_sec  = var.check_interval_sec
  timeout_sec         = var.timeout_sec
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold
  http_health_check {
    request_path = var.https_health_check_request_path
    port         = var.https_health_check_port
  }
}


# Create a Target Pool
resource "google_compute_target_pool" "instance_target_pool" {
  name       = "${var.vm_instance_name}-tp"
  depends_on = [google_compute_health_check.webapp_health_check]
}

# Create a Compute Instance Group
resource "google_compute_region_instance_group_manager" "webapp_instance_group" {
  for_each           = google_compute_network.vpc
  name               = "${each.key}-webapp-instance-group"
  base_instance_name = var.base_instance_name
  # target_size = var.target_size
  region = var.region
  # zone = var.zone

  version {
    name              = "primary"
    instance_template = google_compute_region_instance_template.webapp_template[each.key].self_link
  }

  # target_pools = [google_compute_target_pool.instance_target_pool.self_link]

  named_port {
    name = var.instance_group_named_port_name
    port = var.named_port
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.webapp_health_check[each.key].self_link
    initial_delay_sec = var.initial_delay_sec
  }

  depends_on = [
    google_compute_health_check.webapp_health_check,
    google_compute_region_instance_template.webapp_template
  ]
}

# resource "null_resource" "delay" {
#   for_each = google_compute_network.vpc

#   triggers = {
#     instance_group_id = google_compute_region_instance_group_manager.webapp_instance_group[each.key].id
#   }

#   provisioner "local-exec" {
#     command = "sleep 60"
#   }
# }

# Create a Autoscaler
resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  for_each = google_compute_network.vpc
  name     = "${each.key}-webapp-autoscaler"
  target   = google_compute_region_instance_group_manager.webapp_instance_group[each.key].self_link
  region   = var.region
  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = var.cooldown_period
    cpu_utilization {
      target = var.cpu_utilization_target
    }
  }
  # lifecycle {
  #   create_before_destroy = true
  # }
  depends_on = [
    # null_resource.delay,
    google_compute_health_check.webapp_health_check,
    google_compute_region_instance_group_manager.webapp_instance_group,
    # google_compute_target_pool.instance_target_pool
  ]
}


# Create a Load Balancer with ssl certificate
resource "google_compute_managed_ssl_certificate" "ssl_certificate" {
  for_each = google_compute_network.vpc
  name     = "${each.key}-ssl-certificate"
  managed {
    # domains = google_dns_record_set.webapp_dns[each.key].name
    domains = [google_dns_record_set.webapp_dns[each.key].name]
  }
}

resource "google_compute_target_https_proxy" "webapp_target_https_proxy" {
  for_each         = google_compute_network.vpc
  name             = "${each.key}-webapp-target-https-proxy"
  url_map          = google_compute_url_map.webapp_url_map[each.key].id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_certificate[each.key].name]
  depends_on = [
    google_compute_managed_ssl_certificate.ssl_certificate,
    google_compute_url_map.webapp_url_map
  ]
}

# resource "google_compute_global_address" "webapp_lb_ip" {
#   name = "webapp-lb-ip"
# }

# resource "google_compute_global_forwarding_rule" "webapp_forwarding_rule" {
#   for_each = google_compute_network.vpc
#   name     = "${each.key}-webapp-forwarding-rule"
#   ip_protocol = "TCP"
#   load_balancing_scheme = "EXTERNAL"
#   port_range = "443"
#   target = google_compute_target_https_proxy.webapp_target_https_proxy[each.key].id
#   ip_address = google_compute_global_address.webapp_lb_ip.name
# }

resource "google_compute_global_forwarding_rule" "webapp_forwarding_rule" {
  for_each    = google_compute_network.vpc
  name        = "${each.key}-webapp-forwarding-rule"
  target      = google_compute_target_https_proxy.webapp_target_https_proxy[each.key].id
  ip_protocol = var.forwarding_rule_ip_protocol
  port_range  = var.forwarding_rule_port_range
  ip_address  = google_compute_global_address.webapp_lb_ip[each.key].address
}


resource "google_compute_backend_service" "webapp_backend_service" {
  for_each    = google_compute_network.vpc
  name        = "${each.key}-webapp-backend-service"
  protocol    = var.backend_service_protocol
  port_name   = var.backend_service_port_name
  timeout_sec = var.timeout_sec
  # port_name = "http"
  # locality_lb_policy    = "ROUND_ROBIN"
  health_checks         = [google_compute_health_check.webapp_health_check[each.key].self_link]
  load_balancing_scheme = var.load_balancing_scheme

  backend {
    group           = google_compute_region_instance_group_manager.webapp_instance_group[each.key].instance_group
    balancing_mode  = var.backend_service_balancing_mode
    capacity_scaler = var.backend_service_capacity_scaler
    max_utilization = var.backend_service_max_utilization
  }

  depends_on = [
    google_compute_region_instance_group_manager.webapp_instance_group
  ]
}

resource "google_compute_url_map" "webapp_url_map" {
  for_each        = google_compute_network.vpc
  name            = "${each.key}-webapp-url-map"
  default_service = google_compute_backend_service.webapp_backend_service[each.key].id
}

# resource "google_compute_address" "webapp_lb_ip" {
#   for_each = google_compute_network.vpc
#   name = "${each.key}-webapp-lb-ip"
#   address_type = "EXTERNAL"
#   network_tier = "PREMIUM"
# }

resource "google_compute_global_address" "webapp_lb_ip" {
  for_each = google_compute_network.vpc
  name     = "${each.key}-webapp-lb-ip"
}



# resource "google_compute_global_address" "webapp_lb_ip" {
#   for_each = google_compute_network.vpc
#   name     = "${each.key}-webapp-lb-ip"
# }




# Create a DNS record for the VM instance
resource "google_dns_record_set" "webapp_dns" {
  for_each     = google_compute_network.vpc
  name         = var.dns_name
  type         = var.dns_type
  ttl          = var.dns_ttl
  managed_zone = var.dns_managed_zone
  rrdatas      = [google_compute_global_address.webapp_lb_ip[each.key].address]
}


# service account for cloud function and pubsub
resource "google_service_account" "cloud_function_service_account" {
  for_each     = google_compute_network.vpc
  account_id   = var.cloud_function_service_account_name
  display_name = "Cloud Function Service Account for ${each.key}"
}

# Binding Pub/Sub Subscribe role to the service account
resource "google_project_iam_member" "cloud_function_service_account_binding_pubsub" {
  for_each = google_compute_network.vpc
  role     = "roles/pubsub.subscriber"
  member   = "serviceAccount:${google_service_account.cloud_function_service_account[each.key].email}"
  project  = var.project_id
}

resource "google_project_iam_member" "function_cloudsql_client" {
  for_each = google_compute_network.vpc
  project  = var.project_id
  role     = "roles/cloudsql.client"
  member   = "serviceAccount:${google_service_account.cloud_function_service_account[each.key].email}"
}

# Create a Pub/Sub topic
resource "google_pubsub_topic" "verify_email" {
  for_each = google_compute_network.vpc
  name     = var.pubsub_topic_name
}

# Create a Pub/Sub subscription
resource "google_pubsub_subscription" "subscription" {
  for_each = google_compute_network.vpc
  name     = "verify_email_subscription"
  topic    = google_pubsub_topic.verify_email[each.key].name
  depends_on = [
    google_pubsub_topic.verify_email
  ]
}

# Create Service Account for Bucket
data "google_storage_project_service_account" "gcs_account" {
  project = var.project_id
}

# IAM Binding for Bucket to use KMS key
resource "google_kms_crypto_key_iam_member" "gcs_kms_binding" {
  for_each      = google_compute_network.vpc
  crypto_key_id = google_kms_crypto_key.crypto_key_bucket[each.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = data.google_storage_project_service_account.gcs_account.member
}

resource "google_kms_crypto_key_iam_member" "gcs_kms_binding2" {
  for_each      = google_compute_network.vpc
  crypto_key_id = google_kms_crypto_key.crypto_key_bucket[each.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypter"
  member        = data.google_storage_project_service_account.gcs_account.member
}


# Create a Cloud Bucket for source code zip
resource "google_storage_bucket" "bucket" {
  for_each = google_compute_network.vpc
  name     = "${each.key}-source-code"
  location = var.region
  encryption {
    default_kms_key_name = google_kms_crypto_key.crypto_key_bucket[each.key].id
  }

  depends_on = [
    google_kms_crypto_key_iam_member.gcs_kms_binding
  ]

}

resource "google_storage_bucket_object" "archive" {
  for_each     = google_compute_network.vpc
  name         = "archive.zip"
  bucket       = google_storage_bucket.bucket[each.key].name
  source       = "../CloudFunction/code.zip"
  kms_key_name = google_kms_crypto_key.crypto_key_bucket[each.key].id
}


# Create a VPC Access Connector
resource "google_vpc_access_connector" "serverless_vpc_connector" {
  for_each      = google_compute_network.vpc
  name          = "vpc-conn-${replace(lower(each.key), "_", "-")}"
  ip_cidr_range = var.cidr_vpc_access_connector
  network       = each.value.self_link
}


resource "google_cloudfunctions2_function" "verify_email" {
  for_each    = google_compute_network.vpc
  name        = "verify-email-${each.key}"
  description = "Verify Email"
  location    = var.zone_cloud_function
  build_config {
    runtime     = var.runtime_cloud_function
    entry_point = var.entry_point_cloud_function
    source {
      storage_source {
        bucket = google_storage_bucket.bucket[each.key].name
        object = google_storage_bucket_object.archive[each.key].name
      }
    }
  }
  service_config {
    max_instance_count = 1
    available_memory   = var.available_memory_cloud_function
    timeout_seconds    = 60
    environment_variables = {
      PUBSUB_TOPIC    = google_pubsub_topic.verify_email[each.key].name
      EMAIL_FROM      = var.email_from
      MAILGUN_API_KEY = var.mailgun_api_key
      DB_USER         = google_sql_user.db_user[each.key].name
      DB_PASS         = google_sql_user.db_user[each.key].password
      DB_HOST         = google_sql_database_instance.db_instance[each.key].private_ip_address
      DB_NAME         = google_sql_database.db[each.key].name
      WEBAPP_URL      = var.webapp_url

    }
    service_account_email = google_service_account.cloud_function_service_account[each.key].email
    ingress_settings      = var.ingress_settings_cloud_function
    vpc_connector         = google_vpc_access_connector.serverless_vpc_connector[each.key].id
  }
  event_trigger {
    trigger_region = var.zone_cloud_function
    event_type     = var.event_type_cloud_function
    pubsub_topic   = google_pubsub_topic.verify_email[each.key].id
    retry_policy   = var.retry_policy_cloud_function
  }


  depends_on = [
    google_pubsub_topic.verify_email,
    google_storage_bucket_object.archive
  ]

}

# Create a firewall rule

resource "google_compute_firewall" "allow_http" {

  for_each = google_compute_network.vpc
  name     = "allow-http"
  network  = each.value.self_link
  # direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = var.firewall_allow
  }

  source_ranges = var.route_dest_range_load_balancer

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

# Secret Manager

resource "google_secret_manager_secret" "db_host" {
  for_each  = google_compute_network.vpc
  secret_id = "db-host-${each.key}"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_host" {
  for_each    = google_compute_network.vpc
  secret      = google_secret_manager_secret.db_host[each.key].id
  secret_data = google_sql_database_instance.db_instance[each.key].private_ip_address
}

resource "google_secret_manager_secret" "db_password" {
  for_each  = google_compute_network.vpc
  secret_id = "db-password-${each.key}"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  for_each    = google_compute_network.vpc
  secret      = google_secret_manager_secret.db_password[each.key].id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "vm_kms_key" {
  for_each  = google_compute_network.vpc
  secret_id = "vm-kms-key-${each.key}"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "vm_kms_key" {
  for_each    = google_compute_network.vpc
  secret      = google_secret_manager_secret.vm_kms_key[each.key].id
  secret_data = google_kms_crypto_key.crypto_key_vm[each.key].id
}

# set IAM Permissions for the service account of Packer
resource "google_project_iam_binding" "service_account_binding" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:${var.packer_image_service_account_email}",
  ]
}

resource "google_project_iam_binding" "service_account_binding2" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"

  members = [
    "serviceAccount:${var.packer_image_service_account_email}",
  ]
}

