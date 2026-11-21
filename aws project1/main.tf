# ==============================================================================
# Root Module: Automated Private Image/Document Processor
# Modular Multi-Environment Enterprise Architecture (100% Free Tier)
# ==============================================================================

# 1. Network Module: VPC, Public/Private Subnets, S3 Gateway Endpoint (No NAT)
module "network" {
  source = "./modules/network"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}

# 2. Storage Module: Raw and Processed S3 Buckets, SSE-S3, Public Access Block, Lifecycle Rules
module "storage" {
  source = "./modules/storage"

  project_name            = var.project_name
  environment             = var.environment
  glacier_transition_days = var.glacier_transition_days
  expiration_days         = var.expiration_days
}

# 3. Compute Module: Zero-SSH Security Group, IAM SSM Role, Launch Template, Auto Healing ASG
module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  private_subnet_id     = module.network.private_subnet_id
  raw_bucket_name       = module.storage.raw_bucket_name
  raw_bucket_arn        = module.storage.raw_bucket_arn
  processed_bucket_name = module.storage.processed_bucket_name
  processed_bucket_arn  = module.storage.processed_bucket_arn
  instance_type         = var.instance_type
}
