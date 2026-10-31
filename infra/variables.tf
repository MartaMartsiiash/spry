variable "project_name" {
  type        = string
  description = "Prefix for resource names (Lab 4 PROJECT_NAME)."
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "callback_urls" {
  type = list(string)
  default = [
    "http://localhost:3000/auth/callback/",
  ]
}

variable "logout_urls" {
  type = list(string)
  default = [
    "http://localhost:3000/",
  ]
}

variable "google_client_id" {
  type        = string
  default     = ""
  description = "Google OAuth web client id. Empty disables Google sign-in."
}

variable "google_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Google OAuth client secret. Set in the HCP workspace, not in tfvars."
}

variable "reports_image_uri" {
  type        = string
  description = "ECR image URI (with digest) for the report builder Lambda."
}

variable "parser_image_uri" {
  type        = string
  description = "ECR image URI (with digest) for the agenda parser Lambda."
}

variable "architecture" {
  type    = string
  default = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "builder_architecture" {
  type    = string
  default = "arm64"
}

variable "database_url" {
  type        = string
  sensitive   = true
  description = "Aurora DATABASE_URL for the report builder. Set in HCP workspace."
}

variable "database_iam_auth" {
  type    = string
  default = "false"
}

variable "app_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

variable "schedule_expression" {
  type    = string
  default = "cron(0 7 ? * MON *)"
}

variable "recipient_email" {
  type = string
}

variable "sender_domain" {
  type    = string
  default = ""
}

variable "report_fail_week" {
  type    = string
  default = ""
}

variable "cors_origins" {
  type        = string
  default     = "*"
  description = "Comma-separated origins for the agenda parser function URL."
}

variable "parser_model" {
  type    = string
  default = "eu.anthropic.claude-sonnet-4-6"
}

variable "cognito_user_pool_id" {
  type        = string
  default     = ""
  description = "Filled after import/auth; used by ai.tf. Prefer output reference once in state."
}

variable "cognito_client_id" {
  type    = string
  default = ""
}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  has_google   = var.google_client_id != ""
  has_domain   = var.sender_domain != ""
  reports_bucket_name = "${var.project_name}-reports-${local.account_id}"
  sender_address = local.has_domain ? "reports@${var.sender_domain}" : var.recipient_email
  parser_cors_origins = var.cors_origins == "*" ? ["*"] : split(",", var.cors_origins)
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
