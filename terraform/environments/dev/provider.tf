provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "k8s-hardway"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
