terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
  region = var.aws_region
  profile = "none"
}

data "aws_ids" "current" {}

resource "random_pet" "bucket_name" {
  prefix = "moved"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.bucket_name.id
  acl           = "private"
  force_destroy = true
}


data "archive_file" "moved_zip" {
  type = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
}

resource "aws_s3_bucket_object" "zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "function.zip"
  source = data.archive_file.moved_zip.output_path
  etag = filemd5(data.archive_file.moved_zip.output_path)
}

resource "aws_lambda_function" "moved" {
  function_name = "Moved"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_bucket_object.zip.key

  runtime = "nodejs12.x"
  handler = "index.handler"

  source_code_hash = data.archive_file.moved_zip.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "moved" {
  name = "/aws/lambda/${aws_lambda_function.moved.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}



resource "aws_iam_role_policy" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy     = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:eu-west-2:${data.aws_ids.current.account_id}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:eu-west-2:${data.aws_ids.current.account_id}:*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:UpdateItem",
                "dynamodb:GetItem",
                "dynamodb:PutItem"
            ],
            "Resource": "arn:aws:dynamodb:eu-west-2:${data.aws_ids.current.account_id}:table/LinkTable"
        }
    ]
  })
}



resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "moved"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "moved" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.moved.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "moved" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.moved.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.moved.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}


resource "aws_dynamodb_table" "link-table" {
  name           = "LinkTable"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "From"

  attribute {
    name = "From"
    type = "S"
  }
}

resource "time_static" "build" {}

resource "aws_dynamodb_table_item" "start" {
  table_name = aws_dynamodb_table.link-table.name
  hash_key   = aws_dynamodb_table.link-table.hash_key

  item = <<ITEM
{
  "From": {"S": "/hello"},
  "Views": {"N": "0"},
  "Reached": {"N" : "${time_static.build.unix*1000}"}
}
ITEM
}
