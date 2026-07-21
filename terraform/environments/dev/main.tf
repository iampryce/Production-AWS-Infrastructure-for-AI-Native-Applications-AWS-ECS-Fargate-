# Thin root module — calls reusable modules with dev-specific variables.
# Grows over later phases (rds, redis, ecs, ...) as one stack, one state file.

module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  environment  = "dev"

  # Values come from this environment's terraform.tfvars, not hardcoded
  # here — same main.tf shape works for staging/prod with a different
  # tfvars file.
  nat_type   = var.nat_type
  fck_nat_ha = var.fck_nat_ha

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
