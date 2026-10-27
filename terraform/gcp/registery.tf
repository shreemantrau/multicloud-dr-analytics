// One Docker repository holds both images (web-tier and app-tier), like ACR and unlike ECR.
// No location set, so it uses the provider region (us-west1).
resource "google_artifact_registry_repository" "main" {
  repository_id = "p3-dr"
  format        = "DOCKER"
  description   = "Images for the web and app tiers"

  depends_on = [google_project_service.apis]
}