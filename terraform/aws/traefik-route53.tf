# Traefik Route 53 SSL Configuration
# This creates an IAM user with permissions for Let's Encrypt DNS-01 challenge
# and configures DNS records for the *.lab.hartr.net subdomain

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get the existing Route 53 hosted zone
data "aws_route53_zone" "hartr_net" {
  name = "hartr.net"
}

# IAM policy for Route 53 DNS challenge
resource "aws_iam_policy" "traefik_route53" {
  name        = "traefik-route53-dns-challenge"
  description = "Allow Traefik to create DNS records for Let's Encrypt DNS-01 challenge"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ListHostedZones"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets"
        ]
        Resource = data.aws_route53_zone.hartr_net.arn
      }
    ]
  })

  tags = {
    Purpose     = "Traefik LetsEncrypt DNS-01 Challenge"
    Service     = "Traefik"
    Scope       = "lab.hartr.net subdomain"
    Environment = "homelab"
  }
}

# IAM user for Traefik
resource "aws_iam_user" "traefik_letsencrypt" {
  name = "traefik-letsencrypt"
  path = "/service-accounts/"

  tags = {
    Purpose     = "Traefik LetsEncrypt DNS-01 Challenge"
    Service     = "Traefik"
    Scope       = "lab.hartr.net subdomain"
    Environment = "homelab"
  }
}

# Attach policy to user
resource "aws_iam_user_policy_attachment" "traefik_route53" {
  user       = aws_iam_user.traefik_letsencrypt.name
  policy_arn = aws_iam_policy.traefik_route53.arn
}

# Create access key for the user
resource "aws_iam_access_key" "traefik_letsencrypt" {
  user = aws_iam_user.traefik_letsencrypt.name
}

# Wildcard A record for *.lab.hartr.net pointing to Traefik
resource "aws_route53_record" "lab_wildcard" {
  zone_id = data.aws_route53_zone.hartr_net.zone_id
  name    = "*.lab.hartr.net"
  type    = "A"
  ttl     = 300
  records = [var.traefik_server_ip]

  depends_on = [data.aws_route53_zone.hartr_net]
}

# Optional: specific A record for lab.hartr.net itself
resource "aws_route53_record" "lab_root" {
  zone_id = data.aws_route53_zone.hartr_net.zone_id
  name    = "lab.hartr.net"
  type    = "A"
  ttl     = 300
  records = [var.traefik_server_ip]

  depends_on = [data.aws_route53_zone.hartr_net]
}

# Variables
variable "aws_region" {
  description = "AWS region for Route 53"
  type        = string
  default     = "us-east-1"
}

variable "traefik_server_ip" {
  description = "IP address of your Traefik server (internal IP for homelab access)"
  type        = string
}

# Outputs
output "traefik_aws_access_key_id" {
  description = "AWS Access Key ID for Traefik (store in Nomad variables)"
  value       = aws_iam_access_key.traefik_letsencrypt.id
}

output "traefik_aws_secret_access_key" {
  description = "AWS Secret Access Key for Traefik (store in Nomad variables)"
  value       = aws_iam_access_key.traefik_letsencrypt.secret
  sensitive   = true
}

output "route53_zone_id" {
  description = "Route 53 Hosted Zone ID for hartr.net"
  value       = data.aws_route53_zone.hartr_net.zone_id
}

output "iam_user_arn" {
  description = "ARN of the Traefik IAM user"
  value       = aws_iam_user.traefik_letsencrypt.arn
}

output "dns_records_created" {
  description = "DNS records created for lab subdomain"
  value = {
    wildcard = aws_route53_record.lab_wildcard.fqdn
    root     = aws_route53_record.lab_root.fqdn
  }
}
