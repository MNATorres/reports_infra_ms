terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Asegurate de usar la misma región donde configuraste tus alertas
}

# 1. CREAMOS EL BUCKET DE S3
resource "aws_s3_bucket" "bucket_reportes" {
  # Cambiale el nombre metiendo tu marca personal para que sea único en todo AWS
  bucket = "practica-reportes-s3-matias-2026"

  tags = {
    Name        = "Bucket de Reportes de Empleados"
    Environment = "Dev"
  }
}

# A. DESACTIVAMOS EL BLOQUEO DE ACCESO PÚBLICO DEL BUCKET
resource "aws_s3_bucket_public_access_block" "public_block" {
  bucket = aws_s3_bucket.bucket_reportes.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# B. CREAMOS UNA POLÍTICA PARA QUE CUALQUIERA PUEDA LEER LOS OBJETOS (GetObject)
resource "aws_s3_bucket_policy" "politica_lectura_publica" {
  # Nos aseguramos de que primero se remueva el bloqueo público antes de aplicar la política
  depends_on = [aws_s3_bucket_public_access_block.public_block]
  bucket     = aws_s3_bucket.bucket_reportes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*" # Significa: "Cualquier persona en internet"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.bucket_reportes.arn}/*" # Aplica a todos los archivos dentro
      }
    ]
  })
}

# 2. CREAMOS EL ROL DE IAM PARA LA LAMBDA
resource "aws_iam_role" "lambda_reportes_role" {
  name = "lambda_reportes_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

# 3. POLÍTICA PARA QUE LA LAMBDA ESCRIBA LOGS (Básico para debuggear)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_reportes_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 4. POLÍTICA PERSONALIZADA PARA ESCRIBIR EN EL S3 QUE CREAMOS ARRIBA
resource "aws_iam_policy" "lambda_s3_write_policy" {
  name        = "lambda_s3_write_policy"
  description = "Permite a la Lambda guardar los reportes PDF en su bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.bucket_reportes.arn}/*"
      }
    ]
  })
}

# Enganchamos la política de S3 al rol de la Lambda
resource "aws_iam_role_policy_attachment" "lambda_s3_attach" {
  role       = aws_iam_role.lambda_reportes_role.name
  policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
}

# 5. EMPAQUETADO AUTOMÁTICO DE LA CARPETA REAL
data "archive_file" "lambda_zip_real" {
  type        = "zip"
  source_dir  = "${path.module}/../pdf_generator_employees"
  output_path = "${path.module}/pdf_generator_employees.zip"
}

# 6. ACTUALIZACIÓN DE LA FUNCIÓN LAMBDA
resource "aws_lambda_function" "generador_pdf_lambda" {
  filename      = data.archive_file.lambda_zip_real.output_path
  function_name = "generador-reportes-pdf"
  role          = aws_iam_role.lambda_reportes_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  source_code_hash = data.archive_file.lambda_zip_real.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.bucket_reportes.id
    }
  }
}
