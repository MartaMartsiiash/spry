output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "issuer" {
  value = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "hosted_domain" {
  value = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "google_redirect_uri" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"
}

output "google_enabled" {
  value = local.has_google
}

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "report_queue_url" {
  value = aws_sqs_queue.report_queue.url
}

output "report_dlq_url" {
  value = aws_sqs_queue.report_dlq.url
}

output "builder_function_name" {
  value = aws_lambda_function.builder.function_name
}

output "mailer_function_name" {
  value = aws_lambda_function.mailer.function_name
}

output "sender_address" {
  value = local.sender_address
}

output "parser_url" {
  value = trimsuffix(aws_lambda_function_url.parser.function_url, "/")
}

output "parser_function_name" {
  value = aws_lambda_function.parser.function_name
}

output "parser_log_group_name" {
  value = aws_cloudwatch_log_group.parser.name
}
