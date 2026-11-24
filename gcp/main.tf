# --- APIs: off by default in a new project; enabled here so it is reproducible.
resource "google_project_service" "enabled" {
  for_each           = toset(local.services)
  service            = each.value
  disable_on_destroy = false
}

# --- Artifact Registry (ECR counterpart)
resource "google_artifact_registry_repository" "spry" {
  repository_id = "spry"
  location      = var.region
  format        = "DOCKER"
  description   = "Spry backend images"

  # Keep the free 0.5 GB: only the 3 newest images stay.
  cleanup_policies {
    id     = "keep-latest-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
  cleanup_policies {
    id     = "delete-older"
    action = "DELETE"
    condition {
      older_than = "86400s"
    }
  }

  depends_on = [google_project_service.enabled]
}

# --- Cloud SQL for PostgreSQL (Aurora counterpart). Does NOT pause on idle.
resource "google_sql_database_instance" "db" {
  name             = "spry-db"
  database_version = "POSTGRES_17"
  region           = var.region

  settings {
    tier              = var.db_tier
    edition           = "ENTERPRISE"
    disk_size         = 10
    disk_type         = "PD_SSD"
    disk_autoresize   = false
    availability_type = "ZONAL"
    activation_policy = var.db_activation_policy

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      # Public IP but no authorized networks: only the Cloud SQL connector
      # (Cloud Run's /cloudsql socket, IAM-checked) can reach it.
      ipv4_enabled = true
    }
  }

  deletion_protection = false
  depends_on          = [google_project_service.enabled]
}

resource "google_sql_database" "meetings" {
  name     = "meetings"
  instance = google_sql_database_instance.db.name
}

resource "random_password" "db" {
  length  = 32
  special = false # goes into a URL
}

resource "google_sql_user" "app" {
  name     = "spry"
  instance = google_sql_database_instance.db.name
  password = random_password.db.result
}

# --- Secret Manager: the whole DATABASE_URL, password generated above, never in git.
resource "google_secret_manager_secret" "database_url" {
  secret_id = "spry-database-url"
  replication {
    auto {}
  }
  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "postgresql+asyncpg://${google_sql_user.app.name}:${random_password.db.result}@/${google_sql_database.meetings.name}?host=/cloudsql/${google_sql_database_instance.db.connection_name}"
}

# --- The identity the API runs as (not the default compute SA, which has Editor).
resource "google_service_account" "api" {
  account_id   = "spry-api"
  display_name = "Spry API on Cloud Run"
}

resource "google_project_iam_member" "api_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_reads_db_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

# --- Cloud Run (Lambda counterpart): same Docker image as local, scales to zero.
resource "google_cloud_run_v2_service" "api" {
  count               = var.deploy_service ? 1 : 0
  name                = "spry-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.db.connection_name]
      }
    }

    containers {
      image = local.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true # request-based billing
        startup_cpu_boost = true
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "CORS_ORIGINS"
        value = local.site_origins
      }
      env {
        name  = "APP_TIMEZONE"
        value = var.app_timezone
      }
      env {
        name  = "COGNITO_REGION"
        value = var.cognito_region
      }
      env {
        name  = "COGNITO_USER_POOL_ID"
        value = var.cognito_user_pool_id
      }
      env {
        name  = "COGNITO_CLIENT_ID"
        value = var.cognito_client_id
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      # Migrations run on start (entrypoint.sh), so give the first boot time.
      startup_probe {
        tcp_socket {
          port = 8080
        }
        initial_delay_seconds = 0
        period_seconds        = 5
        failure_threshold     = 24
      }
    }
  }

  depends_on = [
    google_project_iam_member.api_sql_client,
    google_secret_manager_secret_iam_member.api_reads_db_url,
    google_secret_manager_secret_version.database_url,
  ]
}

# The API checks Cognito tokens itself, so the URL can be public.
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.deploy_service ? 1 : 0
  name     = google_cloud_run_v2_service.api[0].name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
