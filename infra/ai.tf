# Was infra/ai.yml (Lab 6). Agenda parser Lambda outside the VPC.

resource "aws_iam_role" "parser" {
  name = "successfulsuccess-ai-ParserRole-jUgcqXTesLUv"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "parser_basic" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser_bedrock" {
  name = "bedrock-converse"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:Converse",
        "bedrock:ConverseStream",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = 14
}

resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Paste-an-agenda parser. Outside the VPC; calls Bedrock; no database."
  role          = aws_iam_role.parser.arn
  package_type  = "Image"
  image_uri     = var.parser_image_uri
  architectures = [var.architecture]
  memory_size   = 512
  timeout       = 30

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  environment {
    variables = {
      CORS_ORIGINS         = var.cors_origins
      LOG_LEVEL            = "INFO"
      COGNITO_REGION       = var.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      PARSER_MODEL         = var.parser_model
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.parser,
    aws_iam_role_policy.parser_bedrock,
  ]
}

resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"

  cors {
    allow_credentials = false
    allow_headers     = ["authorization", "content-type"]
    allow_methods     = ["POST"]
    allow_origins     = local.parser_cors_origins
    max_age           = 86400
  }
}

resource "aws_lambda_permission" "parser_url" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.parser.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_url_invoke" {
  statement_id           = "FunctionURLAllowInvoke"
  action                 = "lambda:InvokeFunction"
  function_name          = aws_lambda_function.parser.function_name
  principal              = "*"
  invoked_via_function_url = true
}
