# 1. Provedor e Variáveis
provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  default = "tech-challenge-fiap-bovespa"
}

# 2. S3 - Data Lake (Requisitos 2 e 6)
resource "aws_s3_bucket" "datalake" {
  bucket        = "${var.project_name}-datalake"
  force_destroy = true 
}

resource "aws_s3_object" "raw_folder" {
  bucket = aws_s3_bucket.datalake.id
  key    = "raw/"
}

resource "aws_s3_object" "refined_folder" {
  bucket = aws_s3_bucket.datalake.id
  key    = "refined/"
}

# Upload do script do Glue
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.datalake.id
  key    = "scripts/etl_job.py"
  source = "${path.module}/../scripts/etl_job.py"
  etag   = filemd5("${path.module}/../scripts/etl_job.py")
}

# 3. Glue Catalog (Requisito 23)
resource "aws_glue_catalog_database" "b3_db" {
  name = "db_bovespa_refined"
}

# 4. IAM Role para o Glue (Permissões Reforçadas)
resource "aws_iam_role" "glue_service_role" {
  name = "GlueBovespaServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
}

# Anexando política gerenciada padrão para Glue
resource "aws_iam_role_policy_attachment" "glue_managed_policy" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Política Customizada para S3 e Catálogo
resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "GlueS3AccessPolicy"
  role = aws_iam_role.glue_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.datalake.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.datalake.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["glue:CreateTable", "glue:UpdateTable", "glue:GetDatabase", "glue:GetTable", "glue:BatchCreatePartition"]
        Resource = ["*"]
      }
    ]
  })
}

# 5. AWS Glue Job (Requisitos 5, 17-21)
resource "aws_glue_job" "bovespa_etl" {
  name     = "job-bovespa-etl-visual"
  role_arn = aws_iam_role.glue_service_role.arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2
  timeout      = 10

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.datalake.bucket}/scripts/etl_job.py"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--DATABASE_NAME"       = aws_glue_catalog_database.b3_db.name
    "--enable-metrics"      = "true"
    "--enable-continuous-cloudwatch-log" = "true"
  }

  # Importante: Depender do Banco e do Script
  depends_on = [
    aws_s3_object.glue_script,
    aws_glue_catalog_database.b3_db
  ]
}

# 6. Lambda e Trigger (Requisitos 15 e 16)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/trigger_glue.py"
  output_path = "${path.module}/lambda_function_payload.zip"
}

resource "aws_lambda_function" "s3_trigger_glue" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "trigger-glue-job-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "trigger_glue.lambda_handler"
  runtime          = "python3.9"
  environment { variables = { GLUE_JOB_NAME = "job-bovespa-etl-visual" } }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger_glue.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.datalake.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.datalake.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger_glue.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
    filter_suffix       = ".parquet"
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}

resource "aws_iam_role" "lambda_role" {
  name = "LambdaTriggerGlueRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_glue_policy" {
  name = "LambdaStartGluePolicy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Action = "glue:StartJobRun", Effect = "Allow", Resource = "*" },
      { Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Effect = "Allow", Resource = "*" }
    ]
  })
}