variable "project_name" {
  type    = string
  default = "aws-ai-native-infra"
}

variable "environment" {
  type = string
}

variable "assets_bucket_force_destroy" {
  description = "true by default so a bucket still holding generated assets doesn't block `terraform destroy` (fast, cheap teardown for dev/staging). Prod's terraform.tfvars should set this to false."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Apex domain, e.g. rivetrecords.online. No Route 53 hosted zone exists yet for this in this account - this module creates one."
  type        = string
}

variable "include_www" {
  description = "Adds www.<domain_name> as a second name on the certificate and (in step 2) a second CloudFront alias."
  type        = bool
  default     = true
}

variable "alb_dns_name" {
  description = "module.ecs.alb_dns_name - CloudFront's default-behavior origin. CloudFront reaches this over the public internet like any custom origin; no VPC-level connectivity involved."
  type        = string
}

variable "waf_rate_limit" {
  description = "Requests per 5-minute window per IP before WAF starts blocking."
  type        = number
  default     = 2000
}

variable "tags" {
  type    = map(string)
  default = {}
}
