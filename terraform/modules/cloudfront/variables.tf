variable "project_name" {
  type    = string
  default = "aws-ai-native-infra"
}

variable "environment" {
  type = string
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

variable "tags" {
  type    = map(string)
  default = {}
}
