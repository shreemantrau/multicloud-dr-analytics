
terraform {
  // Same minimum as the other clouds. The GCS backend locks state natively, no extra setting.
  required_version = ">= 1.10"

  // Backend blocks can't use variables, so the bucket name is written out.
  // prefix = the folder inside the bucket, keeping this cloud's state separate.
  backend "gcs" {
    bucket = "p3-dr-shreyas-tfstate"
    prefix = "gcp"
  }
}