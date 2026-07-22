terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "aws-ai-native-infra-tfstate-1caa89b6"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ACM certificates used by CloudFront must be requested in us-east-1
# specifically, regardless of which region the rest of the stack lives in
# - an explicit alias makes that AWS requirement visible in code rather
# than relying on the fact that this project's primary region already
# happens to be us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
