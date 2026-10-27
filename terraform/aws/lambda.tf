data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


// ---------- S3 bucket: landing zone for Azure's data file ----------
// Bucket names are global, so the account ID keeps it unique.
resource "aws_s3_bucket" "landing" {
  bucket        = "p3-dr-landing-${data.aws_caller_identity.current.account_id}"
  force_destroy = true   // lets terraform destroy delete the bucket even with files inside
}

// New buckets are private by default; this makes it explicit and permanent.
resource "aws_s3_bucket_public_access_block" "landing" {
  bucket                  = aws_s3_bucket.landing.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// ---------- Dead-letter queue: where failed events end up ----------
resource "aws_sqs_queue" "dlq" {
  name                      = "p3-sync-dlq"
  message_retention_seconds = 1209600   // 14 days (the maximum), time to inspect and replay
}

// ---------- Lambda security group ----------
// No ingress: nothing calls the Lambda over the network, S3 invokes it through the AWS API.
// Egress open: it needs RDS, Secrets Manager (via NAT) and S3.
resource "aws_security_group" "lambda" {
  name   = "lambda-p3-sg"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lambda-p3-sg" }
}

// ---------- Lambda role ----------
// Unlike ECS, a Lambda has just one role (no execution/task split).
resource "aws_iam_role" "lambda" {
  name = "p3-sync-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

// Ready-made: write logs + create the network interface a VPC Lambda needs.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

// Ours: three narrow permissions, each limited to one resource.
resource "aws_iam_role_policy" "lambda_sync" {
  name = "sync-permissions"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.landing.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

// ---------- Package: zip the code folder ----------
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/package" //path.module = the folder of this .tf file (terraform/aws) is one level up so no (terraform/aws/lambda), 
                                                // so the paths work no matter which directory terraform is run from.
  output_path = "${path.module}/lambda/sync.zip"
}

// ---------- The function ----------
resource "aws_lambda_function" "sync" {
  function_name = "p3-sync"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "handler.handler"   // file handler.py, function handler()
  timeout       = 30                  // default is 3s, too short for the secret fetch + DB connect

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256   // redeploys when the code changes

  // In the private subnets so it can reach private RDS. The Lambda SG is what RDS allows in.
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST      = aws_db_instance.main.address
      DB_NAME      = "appdb"
      DB_USER      = "dbadmin"
      DB_SECRET_ID = aws_secretsmanager_secret.db.arn
    }
  }

  // Failed async events (after 2 retries) go here.
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  // Lambda checks the role's permissions (including sqs:SendMessage for the DLQ) when it creates
  // the function, so the policies must exist first. It avoid race conditons, terraform applies in parallel
  // below code forces it to make sure parmissions are created first.
  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy.lambda_sync,
  ]
}

// ---------- Trigger: S3 is allowed to invoke the function ----------
resource "aws_lambda_permission" "s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.sync.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.landing.arn
  source_account = data.aws_caller_identity.current.account_id   // only our account's bucket
}

// "A new .csv under incoming/ was uploaded, invoke the function."
resource "aws_s3_bucket_notification" "landing" {
  bucket = aws_s3_bucket.landing.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.sync.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incoming/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.s3]   // the permission must exist before the notification
}

// ---------- S3 gateway endpoint ----------
// Routes S3 traffic from the private subnets over AWS's network instead of the NAT.
// Gateway endpoints are free.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}