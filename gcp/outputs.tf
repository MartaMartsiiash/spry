output "api_url" {
  value = var.deploy_service ? google_cloud_run_v2_service.api[0].uri : ""
}

output "site_url" {
  value = "https://${var.project_id}.web.app"
}

output "image" {
  value = local.image
}

output "db_connection_name" {
  value = google_sql_database_instance.db.connection_name
}
