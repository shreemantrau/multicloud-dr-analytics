// Cloud SQL instance names can't be reused for about a week after deletion,
// so every rebuild gets a new random suffix. Check providers.tf
resource "random_id" "db_suffix" {
  byte_length = 2
}

// ---------- Private services access: how Cloud SQL gets a private IP ----------
// Cloud SQL runs in a Google-managed network. We reserve an address range in our VPC
// and peer the two networks, so the database gets a private IP from that range.

// Step 1: reserve a block of private addresses in our VPC for Google's managed services.
// Nothing is connected yet; this just sets the range aside so nothing else uses it.
resource "google_compute_global_address" "sql_range" {
  name          = "sql-private-range"
  purpose       = "VPC_PEERING" // marks the range as reserved for peering with a Google service
  address_type  = "INTERNAL"    // private addresses only
  prefix_length = 20            // /20 = 4,096 addresses
  network       = google_compute_network.main.id
}

// Step 2: peer our VPC with Google's service network, using the reserved range.
// Cloud SQL then takes its private IP from that range.
resource "google_service_networking_connection" "sql" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.sql_range.name]

  // Destroy often fails with "producer services still using this connection" while the
  // instance is still being deleted. ABANDON skips deleting the peering itself.
  deletion_policy = "ABANDON"

  depends_on = [google_project_service.apis]
}


// ---------- Cloud SQL (Postgres), private only ----------
// No region set, so it uses the provider region (us-west1).
resource "google_sql_database_instance" "main" {
  name             = "p3-postgres-${random_id.db_suffix.hex}" //writes as 4 characters from 0-9 and a-f. So the instance name comes out like p3-postgres-a3f9
  database_version = "POSTGRES_16"

  // The provider default is true, which blocks terraform destroy.
  deletion_protection = false

  settings {
    tier              = "db-f1-micro" // smallest shared-core size, the cheapest option
    edition           = "ENTERPRISE"  // db-f1-micro isn't available in the other edition
    availability_type = "ZONAL"       // no standby copy (REGIONAL would be real high availability)
    disk_size         = 10            // GB, the minimum

    ip_configuration {
      ipv4_enabled    = false // no public IP
      private_network = google_compute_network.main.id
    }

    backup_configuration {
      enabled = false // demo only
    }
  }

  depends_on = [google_service_networking_connection.sql]
}

resource "google_sql_database" "app" {
  name     = "appdb"
  instance = google_sql_database_instance.main.name
}