# Spry on Google Cloud (Lab 9). Separate from infra/ (AWS) on purpose:
# its own HCP Terraform workspace and state, so one plan can never break both clouds.
terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "successfulsuccess-Martsiiash"

    workspaces {
      # Execution mode: Local — the plan runs in Cloud Shell with your gcloud
      # credentials (no service account key anywhere); only the state lives in HCP.
      name = "successfulsuccess-gcp"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project    = "spry"
    managed-by = "terraform"
  }
}
