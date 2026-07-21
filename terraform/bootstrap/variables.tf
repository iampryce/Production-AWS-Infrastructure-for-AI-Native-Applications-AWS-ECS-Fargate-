variable "project_name" {
  description = "Short project identifier, used as a prefix for backend resource names."
  type        = string
  default     = "project9-ai-native-infra"
}

variable "aws_region" {
  description = "AWS region the state bucket and lock table live in."
  type        = string
  default     = "us-east-1"
}
