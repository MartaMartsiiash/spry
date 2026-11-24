variable "project_id" {
  type        = string
  description = "Google Cloud project ID (permanent, globally unique), e.g. spry-martsiiash-2026."
}

variable "region" {
  type        = string
  default     = "europe-west1"
  description = "Belgium: Tier 1 prices (same as us-central1), close to Ukraine, and Firebase Hosting can rewrite to Cloud Run here."
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag of the backend image in Artifact Registry. deploy.sh passes the git commit."
}

variable "deploy_service" {
  type        = bool
  default     = true
  description = "False on the very first apply, before the image exists in Artifact Registry."
}

variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}

variable "db_activation_policy" {
  type        = string
  default     = "ALWAYS"
  description = "ALWAYS = running and billed per hour; NEVER = stopped (only storage is billed)."
}

# Sign-in stays on AWS for now (Cognito). These values are public: they are
# already in the frontend bundle served from CloudFront.
variable "cognito_region" {
  type    = string
  default = "eu-north-1"
}

variable "cognito_user_pool_id" {
  type    = string
  default = "eu-north-1_8JgjHup8F"
}

variable "cognito_client_id" {
  type    = string
  default = "7ridr6t0t0bqmn16s25uu2qsc5"
}

variable "app_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

locals {
  services = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
  ]

  image        = "${var.region}-docker.pkg.dev/${var.project_id}/spry/backend:${var.image_tag}"
  site_origins = "https://${var.project_id}.web.app,https://${var.project_id}.firebaseapp.com,http://localhost:3000"
}
