// One identity per tier. Without these, Cloud Run would use the default service account,
// which has broad Editor access to the project.
resource "google_service_account" "app" {
  account_id   = "sa-app-p3"
  display_name = "App tier"

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "web" {
  account_id   = "sa-web-p3"
  display_name = "Web tier" // gets no permissions of its own

  depends_on = [google_project_service.apis]
}

// Least privilege: only the app may read secrets, and only this one secret.
// Azure equivalent: Key Vault Secrets User. AWS equivalent: the task role's GetSecretValue.
resource "google_secret_manager_secret_iam_member" "app_reads_db_password" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}