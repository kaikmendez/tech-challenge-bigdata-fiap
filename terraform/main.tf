# 1. Provedor e Variáveis
provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  default = "tech-challenge-fiap-bovespa"
}

# 2. S3 - Data Lake (Requisitos 2 e 6)
resource "aws_s3_bucket" "datalake" {
  bucket = "${var.project_name}-datalake"
}

# Criação das pastas Raw e Refined (Requisito 14 e 21)
resource "aws_s3_object" "raw_folder" {
  bucket = aws_s3_bucket.datalake.id
  key    = "raw/"
}

resource "aws_s3_object" "refined_folder" {
  bucket = aws_s3_bucket.datalake.id
  key    = "refined/"
}

# 3. Glue Catalog (Requisito 23)
resource "aws_glue_catalog_database" "b3_db" {
  name = "db_bovespa_refined"
}

# 4. IAM Role para o Glue (Permissões de leitura/escrita)
resource "aws_iam_role" "glue_service_role" {
  name = "GlueBovespaServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
}

# 5. AWS Glue Job - Modo Visual (Requisito 15, 17-21)
resource "aws_glue_job" "bovespa_etl" {
  name     = "job-bovespa-etl-visual"
  role_arn = aws_iam_role.glue_service_role.arn
  glue_version = "4.0"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.datalake.bucket}/scripts/etl_job.py"
  }

  default_arguments = {
    "--job-language" = "python"
    "--DATABASE_NAME" = aws_glue_catalog_database.b3_db.name
  }
}

# 6. AWS Lambda - O Gatilho (Requisito 15 e 16)
resource "aws_lambda_function" "s3_trigger_glue" {
  filename      = "lambda_function_payload.zip" # Você deve zipar seu script da lambda
  function_name = "trigger-glue-job-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "trigger_glue.lambda_handler"
  runtime       = "python3.9"

  environment {
    variables = {
      GLUE_JOB_NAME = aws_glue_job.bovespa_etl.name
    }
  }
}

# 7. Configuração do Gatilho S3 -> Lambda (Requisito 15)
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.datalake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger_glue.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
    filter_suffix       = ".parquet"
  }
}