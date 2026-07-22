# No hosted zone existed in this AWS account for this domain - it was
# registered at Namecheap and left on Namecheap's own DNS. Created here,
# not looked up via data source. After this applies, the domain's
# nameservers at the registrar need to be updated to the ones this zone
# is assigned (see the zone_name_servers output) before ACM's DNS
# validation (added in step 2, once that delegation has propagated) can
# actually succeed.
resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = var.tags
}
