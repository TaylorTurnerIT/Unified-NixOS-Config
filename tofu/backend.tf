# tofu/backend.tf
# OpenTofu remote state backend — MinIO on VM2.
# DEFERRED to Phase 2. MinIO must be running before this is activated.
# Bootstrap procedure: run tofu init locally first, apply to create MinIO bucket,
# then migrate state with: tofu init -migrate-state

# terraform {
#   backend "s3" {
#     bucket                      = "tofu-state"
#     key                         = "global/terraform.tfstate"
#     region                      = "us-east-1"  # MinIO ignores region but requires a value
#     endpoint                    = "https://minio.internal.tongatime.us"
#     force_path_style            = true
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#   }
# }
