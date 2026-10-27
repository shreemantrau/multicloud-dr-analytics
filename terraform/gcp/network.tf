// Custom mode: we define the subnets ourselves. Auto mode would create one subnet in every region.
// we have the region set in providers.tf but it will override and create subnets in each region if 
// auto_create_subnetworks is not set to false
// in our code since we have it to flase it will no chose the region from the providers.tf 


resource "google_compute_network" "main" { // This is equivalent to VNET (Azure) or VPC (AWS)
  name                    = "vpc-p3-dr"
  auto_create_subnetworks = false

  // The Compute API must be enabled first. Prevents Race condition when we deploy all of the code at once.
  depends_on = [google_project_service.apis]
}

// ip_address - 10.2.x so it doesn't overlap Azure (10.0) or AWS (10.1) if the clouds are connected later.
resource "google_compute_subnetwork" "main" {
  name          = "snet-p3-dr"
  ip_cidr_range = "10.2.1.0/24"
  network       = google_compute_network.main.id

  // Resources here have no public IP, so they can't reach anything outside the VPC by default.
  // This lets them reach Google's own services (Artifact Registry, Secret Manager) over Google's
  // internal network instead: the GCP answer to the NAT we needed on AWS.
  // Outbound only. It doesn't open the subnet to anyone.
  private_ip_google_access = true
}