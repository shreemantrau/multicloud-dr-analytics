terraform {
  backend "s3" {
    bucket       = "p3-tfstate-966981264807" # the bucket
    key          = "aws.tfstate"             # file name of the state inside the bucket
    region       = "us-west-2"
    use_lockfile = true # lock file in S3 stops two applies at once
    encrypt      = true # encrypt the state file at rest
  }
}