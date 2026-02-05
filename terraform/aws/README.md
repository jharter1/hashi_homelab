# AWS Traefik Route 53 Configuration

This directory contains Terraform configuration for setting up Traefik SSL with Let's Encrypt and Route 53.

## Quick Start

1. **Copy example variables**:
   ```bash
   cd terraform/aws
   cp terraform.tfvars.example terraform.tfvars
   nano terraform.tfvars  # Update with your Traefik IP
   ```

2. **Initialize and apply**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Save credentials** (shown once):
   ```bash
   export AWS_ACCESS_KEY_ID=$(terraform output -raw traefik_aws_access_key_id)
   export AWS_SECRET_ACCESS_KEY=$(terraform output -raw traefik_aws_secret_access_key)
   
   # Store in Nomad variables
   nomad var put nomad/jobs/traefik \
     aws_access_key="$AWS_ACCESS_KEY_ID" \
     aws_secret_key="$AWS_SECRET_ACCESS_KEY"
   ```

4. **Verify DNS records**:
   ```bash
   dig *.lab.hartr.net
   dig calibre.lab.hartr.net
   ```

## What This Creates

- **IAM User**: `traefik-letsencrypt` with minimal Route 53 permissions
- **IAM Policy**: Allows DNS record creation for Let's Encrypt challenges
- **Access Keys**: For Traefik to authenticate with AWS
- **DNS Records**: 
  - `*.lab.hartr.net` → Your Traefik server IP
  - `lab.hartr.net` → Your Traefik server IP

## Security Notes

- Access keys are stored in Terraform state (keep secure)
- Consider using remote state (S3 + DynamoDB) for production
- To rotate keys: `terraform taint aws_iam_access_key.traefik_letsencrypt && terraform apply`
- Never commit `terraform.tfvars` or `terraform.tfstate` to git

## Outputs

- `traefik_aws_access_key_id` - Store in Nomad variables
- `traefik_aws_secret_access_key` - Store in Nomad variables (sensitive)
- `route53_zone_id` - Zone ID for hartr.net
- `iam_user_arn` - ARN of created IAM user
- `dns_records_created` - Confirmation of DNS records

## Next Steps

After applying this configuration:
1. Update Nomad client configuration to add `traefik-acme` host volume
2. Update Traefik job to use Let's Encrypt with Route 53
3. Deploy services with SSL tags

See `docs/TRAEFIK_SSL_SETUP.md` for complete deployment guide.
