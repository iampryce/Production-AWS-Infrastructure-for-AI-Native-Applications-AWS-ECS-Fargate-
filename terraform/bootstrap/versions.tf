terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Intentionally no backend block here — this module creates the S3
  # bucket + DynamoDB table that every other root module's backend points
  # at, so it must run against local state. Applied once, by hand.
}
