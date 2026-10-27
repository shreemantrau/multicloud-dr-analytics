// A new project has almost everything switched off. Each service we use needs its API enabled first.
// for_each = one resource per item in the list.
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",              // VPC, subnets, firewall rules
    "servicenetworking.googleapis.com",    // private IP connection to Cloud SQL
    "sqladmin.googleapis.com",             // Cloud SQL
    "artifactregistry.googleapis.com",     // container images
    "secretmanager.googleapis.com",        // secrets
    "run.googleapis.com",                  // Cloud Run
    "iam.googleapis.com",                  // service accounts and roles
    "cloudresourcemanager.googleapis.com", // project-level IAM
  ])

  service = each.key //each is used to iterate through the set above

  // Keep the APIs enabled on destroy: disabling is slow, can fail on leftover dependencies,
  // and enabled APIs cost nothing.
  disable_on_destroy = false
}