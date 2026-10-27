// ECR repository for the web tier image. Same job as Azure ACR, but AWS has one repository per image name.
resource "aws_ecr_repository" "web" {
  name = "web-tier" // the "true name" in the image name: <account>.dkr.ecr.us-west-2.amazonaws.com/web-tier:v1

  // IMMUTABLE: a tag can't be overwritten once pushed, so v1 always means the same image.
  // Push a new tag for every change (v2, v3...). 
  // Flipped to MUTABLE to speed up things.
  image_tag_mutability = "MUTABLE"

  // Without this, destroy fails while the repository still holds images.
  force_delete = true

  // Free vulnerability scan every time an image is pushed.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "ecr-web-tier" }
}

// ECR repository for the app tier image.
resource "aws_ecr_repository" "app" {
  name                 = "app-tier"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "ecr-app-tier" }
}