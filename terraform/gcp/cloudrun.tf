
// ---------- App tier: private Cloud Run service ----------
// No "allUsers" invoker below, so only callers with an authorized ID token get in.
// The location comes from the subnet so the two always match.
resource "google_cloud_run_v2_service" "app" {
  name     = "p3-app"
  location = google_compute_subnetwork.main.region

  // The provider default is true, which blocks terraform destroy.
  deletion_protection = false

  template {
    service_account = google_service_account.app.email // the identity that reads the secret ... iam.tf

    scaling {
      min_instance_count = 0 // scales to zero when idle: nothing is billed between requests
      max_instance_count = 1
    }

    // Direct VPC egress: the container gets an address in our subnet, so it can reach
    // Cloud SQL's private IP over the peering. PRIVATE_RANGES_ONLY sends only private-IP
    // traffic through the VPC; everything else (Secret Manager) goes out the normal way.
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = google_compute_network.main.id
        subnetwork = google_compute_subnetwork.main.id
      }
    }

    containers {
      image = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${google_artifact_registry_repository.main.project}/${google_artifact_registry_repository.main.repository_id}/app-tier:v1"

      ports {
        container_port = 5000 // Flask; Cloud Run defaults to 8080
      }
      // Each env block sets one environment variable inside the container; 
      // the provider takes one name/value pair per block. app.py reads these at startup.
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.main.private_ip_address
      }
      env {
        name  = "DB_NAME"
        value = "appdb"
      }
      env {
        name  = "DB_USER"
        value = "dbadmin"
      }
      // The app reads the password itself at runtime; only the secret's path is passed in.
      env {
        name  = "DB_SECRET_ID"
        value = "${google_secret_manager_secret.db_password.id}/versions/latest"
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_iam_member.app_reads_db_password,
  ]
}

// ---------- Web tier: public Cloud Run service ----------
resource "google_cloud_run_v2_service" "web" {
  name                = "p3-web"
  location            = google_compute_subnetwork.main.region
  deletion_protection = false

  template {
    service_account = google_service_account.web.email

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${google_artifact_registry_repository.main.project}/${google_artifact_registry_repository.main.repository_id}/web-tier:v1"

      ports {
        container_port = 5000
      }

      env {
        name  = "APP_URL"
        value = google_cloud_run_v2_service.app.uri // the app's run.app URL
      }
      env {
        name  = "CLOUD_NAME"
        value = "GCP"
      }
    }
  }

  depends_on = [google_project_service.apis]
}

// ---------- Who may call what ----------
// Anyone on the internet may call the web tier (its public entry point).
resource "google_cloud_run_v2_service_iam_member" "web_public" {
  name     = google_cloud_run_v2_service.web.name
  location = google_cloud_run_v2_service.web.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

// Only the web tier's service account may call the app tier.
resource "google_cloud_run_v2_service_iam_member" "app_from_web" {
  name     = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.web.email}"
}

// Prints the web tier's public URL after apply, so we can curl it without looking it up in the console.
output "web_url" {
  value = google_cloud_run_v2_service.web.uri
}