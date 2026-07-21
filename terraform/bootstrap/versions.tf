terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Intentionally no backend block here — this module creates the S3
  # bucket that every other root module's backend points at (with native
  # S3 locking, use_lockfile = true — no DynamoDB table needed), so it
  # must run against local state. Applied once, by hand.
}
