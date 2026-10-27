// Cloud SQL doesn't generate a password for us the way RDS did, so we create one here.
// Letters and digits only (special = false), so it can't break a connection string.
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "google_sql_user" "app" {
  name     = "dbadmin"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

// The secret is the container; each version holds a value. Like Key Vault, the app reads it at runtime.
resource "google_secret_manager_secret" "db_password" {
  secret_id = "p3-db-password"

  replication {
    auto {} // Google chooses the storage regions
  }

  depends_on = [google_project_service.apis]
}

// The value: each version holds one password string. Storing a new value adds it to the list
// and the app reads "latest" (the newest version). Old versions stay available for rollback. 
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}