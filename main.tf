# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "hello_world_lambda" {
  function_name = "HelloWorldLambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  filename      = "function.zip"
}

# 3. Cognito User Pool (for SSO)
resource "aws_cognito_user_pool" "user_pool" {
  name = "HelloWorldUserPool"
  
  password_policy {
    minimum_length = 8
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  auto_verified_attributes = ["email"]
  mfa_configuration = "OFF"
}

resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  username     = var.username
  password     = var.password
}

# resource "aws_cognito_user_pool_client" "app_client" {
 # name           = "HelloWorldAppClient"
 # user_pool_id   = aws_cognito_user_pool.user_pool.id
 # generate_secret = false
# }

resource "aws_cognito_user_pool_client" "app_client" {
  name                     = "HelloWorldAppClient"
  user_pool_id             = aws_cognito_user_pool.user_pool.id
  generate_secret          = true
  callback_urls            = ["https://k7cjb5aqdc.execute-api.us-east-1.amazonaws.com/dev/hello"]  # Your API endpoint for handling the callback
  allowed_oauth_flows      = ["code", "implicit"] # Use the authorization code grant flow for OAuth
  allowed_oauth_scopes     = ["openid", "email", "profile"]  # OpenID scope and others if needed
  allowed_oauth_flows_user_pool_client = true
  prevent_user_existence_errors        = "ENABLED"
}

}

# API Gateway Rest API
resource "aws_api_gateway_rest_api" "api" {
  name        = "HelloWorldAPI"
  description = "API for HelloWorld Lambda"
}

# Create resource (path /hello)
resource "aws_api_gateway_resource" "hello_world_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

# Create method (GET) for the resource /hello
resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello_world_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# Integrate the GET method with the Lambda function
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello_world_resource.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.hello_world_lambda.arn}/invocations"
}

# Grant API Gateway permission to invoke the Lambda function
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}

# Enable CORS for the GET method (optional, if you're calling this from a browser)
resource "aws_api_gateway_method_response" "method_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello_world_resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = true
    "method.response.header.Access-Control-Allow-Headers"     = true
    "method.response.header.Access-Control-Allow-Methods"     = true
  }
}

resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello_world_resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"      = "'*'"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods"     = "'OPTIONS,GET,PUT,POST,DELETE'"
  }

  depends_on = [aws_api_gateway_integration.lambda_integration]
}

# 10. Cognito Authorizer for API Gateway
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "CognitoAuthorizer"
  rest_api_id     = aws_api_gateway_rest_api.api.id
  identity_source = "method.request.header.Authorization"
  provider_arns   = [aws_cognito_user_pool.user_pool.arn]
  type            = "COGNITO_USER_POOLS"  # This can be omitted as it defaults to COGNITO_USER_POOLS
}


# Create API Gateway deployment
resource "aws_api_gateway_deployment" "my_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method.get_method
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

# Explicitly create an API Gateway stage
resource "aws_api_gateway_stage" "dev_stage" {
  rest_api_id  = aws_api_gateway_rest_api.api.id
  stage_name   = "dev"
  deployment_id = aws_api_gateway_deployment.my_api_deployment.id
}

# Output the API URL
output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/dev/hello"
}
