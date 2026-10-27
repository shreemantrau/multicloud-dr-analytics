terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      // ~> 6.0 = any 6.x. Pinned to a major version so a new major release can't surprise us.
      version = "~> 6.0"
    }
    // Generates random values inside Terraform, kept in state so they stay the same on later applies.
    // Cloud SQL: a deleted instance's name can't be reused for about a week, so each rebuild
    // needs a new name suffix. This makes life easy and helps us apply with new suffix at rapid pace.
    // Password: the database needs one, and generating it here keeps it out of the code.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

// Credentials come from the application-default login, so no keys appear in the code.
provider "google" {
  project = "p3-dr-shreyas"
  region  = "us-west1" // Oregon, the same area as AWS us-west-2
}