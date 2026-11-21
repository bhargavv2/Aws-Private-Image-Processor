# ==============================================================================
# Outputs: Project Summary & Enterprise Verification Guides
# ==============================================================================

output "network_summary" {
  description = "Network topology details"
  value = {
    vpc_id             = module.network.vpc_id
    vpc_cidr           = module.network.vpc_cidr
    public_subnet_id   = module.network.public_subnet_id
    private_subnet_id  = module.network.private_subnet_id
    s3_vpc_endpoint_id = module.network.s3_endpoint_id
  }
}

output "storage_summary" {
  description = "Storage configuration details"
  value = {
    raw_ingestion_bucket = module.storage.raw_bucket_name
    processed_bucket     = module.storage.processed_bucket_name
    lifecycle_glacier    = "${var.glacier_transition_days} days"
    lifecycle_delete     = "${var.expiration_days} days"
    encryption           = "SSE-S3 (AES256)"
    public_access_block  = "Enforced (Zero public exposure)"
  }
}

output "compute_summary" {
  description = "Compute & Auto Scaling configuration"
  value = {
    asg_name          = module.compute.asg_name
    security_group_id = module.compute.security_group_id
    inbound_rules     = "0 rules (Zero-SSH Port 22 closed)"
    iam_role          = module.compute.iam_role_name
    management_method = "AWS Systems Manager (SSM) Session Manager"
  }
}

output "quick_test_commands" {
  description = "Commands to test the end-to-end pipeline using AWS CLI"
  value = <<-EOT
    # 1. Upload a raw test file:
    aws s3 cp test_assets/sample.txt s3://${module.storage.raw_bucket_name}/sample.txt

    # 2. Watch the worker process it and upload to processed bucket:
    aws s3 ls s3://${module.storage.processed_bucket_name}/documents/

    # 3. Verify original raw file was automatically purged:
    aws s3 ls s3://${module.storage.raw_bucket_name}/
  EOT
}
