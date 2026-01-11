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

# 6. Automação do ZIP da Lambda
# Este bloco gera o arquivo ZIP automaticamente a partir do seu script Python
data "archive_file" "lambda_zip" {
  type        = "zip"
  # Note que agora o caminho aponta para /src/lambda/
  source_file = "${path.module}/../src/lambda/trigger_glue.py"
  output_path = "${path.module}/lambda_function_payload.zip"
}

# 7. AWS Lambda - O Gatilho (Requisito 15 e 16)
resource "aws_lambda_function" "s3_trigger_glue" {
  # Usa o arquivo gerado automaticamente pelo bloco archive_file acima
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
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

# 8. Permissão para o S3 invocar a Lambda (NOVO)
# Sem isso, o S3 tenta avisar a Lambda, mas a AWS bloqueia o acesso
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger_glue.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.datalake.arn
}

# 9. Configuração do Gatilho S3 -> Lambda (Requisito 15)
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.datalake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger_glue.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
    filter_suffix       = ".parquet"
  }
  
  # Garante que a permissão de invocação seja criada antes do gatilho
  depends_on = [aws_lambda_permission.allow_bucket]
}

# 10. Criação da Identidade da Lambda (Role)
resource "aws_iam_role" "lambda_role" {
  name = "LambdaTriggerGlueRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 11. Permissão para a Lambda iniciar o Job do Glue
resource "aws_iam_role_policy" "lambda_glue_policy" {
  name = "LambdaStartGluePolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "glue:StartJobRun"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}