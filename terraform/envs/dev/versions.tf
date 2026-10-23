terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70" # any 6.x from 6.70; exact version pinned in .terraform.lock.hcl
    }
  }

  # State is stored locally by default (and git-ignored). Before a real or
  # shared deployment, switch to an encrypted S3 backend with native locking:
  #
  # backend "s3" {
  #   bucket       = "<your-unique-state-bucket>"
  #   key          = "aws-multi-region-ecommerce/dev/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
