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

module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = "dev"

  data_subnet_ids   = values(module.network.data_subnet_ids)
  security_group_id = module.network.data_security_group_id

  # From this environment's terraform.tfvars — false in dev, no default in
  # the module itself.
  multi_az = var.multi_az

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

module "redis" {
  source = "../../modules/redis"

  project_name = var.project_name
  environment  = "dev"

  data_subnet_ids   = values(module.network.data_subnet_ids)
  security_group_id = module.network.data_security_group_id

  # From this environment's terraform.tfvars — false in dev, no default in
  # the module itself.
  automatic_failover_enabled = var.automatic_failover_enabled

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

module "ecs" {
  source = "../../modules/ecs"

  project_name = var.project_name
  environment  = "dev"

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = values(module.network.public_subnet_ids)
  app_subnet_ids        = values(module.network.app_subnet_ids)
  alb_security_group_id = module.network.alb_security_group_id
  app_security_group_id = module.network.app_security_group_id

  rds_master_user_secret_arn = module.rds.master_user_secret_arn
  rds_host                   = module.rds.db_address
  rds_db_name                = module.rds.db_name
  rds_master_username        = module.rds.master_username

  redis_auth_token_secret_arn    = module.redis.auth_token_secret_arn
  redis_primary_endpoint_address = module.redis.primary_endpoint_address
  redis_port                     = module.redis.port

  # Phase 5's image-build-deploy pipeline has now pushed a real image to
  # :prod on both repos (verified: tags 72da7b8 + prod present on both) -
  # safe to flip. See ADR-006.
  use_placeholder_images = false

  # Deliberately NOT module.cloudfront.assets_bucket_name - that module
  # depends on module.ecs.alb_dns_name, so referencing its output back
  # here would be a module dependency cycle. The name is fully
  # deterministic, matching cloudfront/s3.tf exactly (see ecs module's
  # own variables.tf comment).
  assets_bucket_name = "${var.project_name}-dev-assets"
  assets_bucket_arn  = "arn:aws:s3:::${var.project_name}-dev-assets"
  # Site root, not "/assets" - the worker's own S3 key already carries
  # the "assets/" prefix CloudFront's /assets/* behavior expects, so
  # this base plus that key produces the correct public URL without
  # doubling up the segment.
  public_asset_base_url = "https://${var.domain_name}"

  openai_api_key = var.openai_api_key

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

module "cloudflare_tunnel" {
  source = "../../modules/cloudflare-tunnel"

  project_name = var.project_name
  environment  = "dev"

  ops_subnet_id         = module.network.ops_subnet_id
  ops_security_group_id = module.network.ops_security_group_id
  cloudflare_account_id = var.cloudflare_account_id

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

module "flagsmith" {
  source = "../../modules/flagsmith"

  project_name = var.project_name
  environment  = "dev"

  vpc_id                = module.network.vpc_id
  ops_subnet_id         = module.network.ops_subnet_id
  ops_security_group_id = module.network.ops_security_group_id
  data_subnet_ids       = values(module.network.data_subnet_ids)

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name = var.project_name
  environment  = "dev"

  ops_subnet_id         = module.network.ops_subnet_id
  ops_security_group_id = module.network.ops_security_group_id

  ecs_cluster_name                = module.ecs.cluster_name
  fastapi_service_name            = module.ecs.fastapi_service_name
  celery_service_name             = module.ecs.celery_service_name
  alb_arn_suffix                  = module.ecs.alb_arn_suffix
  fastapi_target_group_arn_suffix = module.ecs.fastapi_target_group_arn_suffix

  rds_db_instance_id = module.rds.db_instance_id

  redis_replication_group_id     = module.redis.replication_group_id
  redis_primary_endpoint_address = module.redis.primary_endpoint_address
  redis_port                     = module.redis.port
  redis_auth_token_secret_arn    = module.redis.auth_token_secret_arn

  # slack_webhook_url and grafana_cloud_api_key have no corresponding
  # entry in terraform.tfvars on purpose - they're sensitive and come only
  # from TF_VAR_-prefixed env vars in CI (terraform-dev.yml), never a
  # committed file.
  slack_webhook_url           = var.slack_webhook_url
  grafana_cloud_otlp_endpoint = var.grafana_cloud_otlp_endpoint
  grafana_cloud_instance_id   = var.grafana_cloud_instance_id
  grafana_cloud_api_key       = var.grafana_cloud_api_key

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = "dev"
  domain_name  = var.domain_name
  alb_dns_name = module.ecs.alb_dns_name

  tags = {
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
