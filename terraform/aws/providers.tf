terraform {
  required_version = ">=1.10" # use_lockfile in backend.tf needs 1.10+
  required_providers {
    aws = {
      source = "hashicorp/aws"
      // 6.69.0 has a bug that breaks zip uploads to Lambda ("bufio.Scanner: token too long").
      // Cap it below that version until a fix is released.
      version = ">= 6.0, < 6.69.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
  # Every resource we create gets these tags automatically (cost tracking, cleanup).
  default_tags {
    tags = {
      Project = "project3-multicloud-dr"
      Managed = "terraform"
    }
  }
}