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

resource "aws_lambda_function" "hello_world_lambda" {
  function_name = "HelloWorldLambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "Node.js 18.x"
  filename      = "function.zip"
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "HelloWorldAPI"
  description = "API for HelloWorld Lambda"
}

resource "aws_api_gateway_resource" "hello_world_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello_world_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello_world_resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                        = "AWS_PROXY"
  uri                         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.hello_world_lambda.arn}/invocations"
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}

