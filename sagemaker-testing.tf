provider "aws" {
  region = "us-west-2"
}

# Module for VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.0"

  name = "sagemaker-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Name = "sagemaker-vpc"
  }
}

# Module for S3 bucket
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "2.0.0"

  bucket = "sagemaker-model-storage"
  acl    = "private"

  tags = {
    Name        = "sagemaker-model-storage"
    Environment = "dev"
  }
}

# IAM role for SageMaker
resource "aws_iam_role" "sagemaker_execution" {
  name = "sagemaker_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "sagemaker.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "sagemaker_execution_role"
  }
}

resource "aws_iam_role_policy" "sagemaker_execution_policy" {
  role = aws_iam_role.sagemaker_execution.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "sagemaker:CreateTrainingJob",
          "sagemaker:CreateModel",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:CreateEndpoint",
          "sagemaker:InvokeEndpoint"
        ],
        Resource = "*"
      }
    ]
  })
}

# SageMaker Model
resource "aws_sagemaker_model" "sagemaker_model" {
  name                 = "sagemaker-model"
  execution_role_arn   = aws_iam_role.sagemaker_execution.arn
  primary_container {
    image             = "763104351884.dkr.ecr.us-west-2.amazonaws.com/pytorch-inference:1.7.1-cpu-py36-ubuntu18.04"
    model_data_url    = "s3://${module.s3_bucket.bucket}/model.tar.gz"
    environment = {
      SAGEMAKER_CONTAINER_LOG_LEVEL = "20"
      SAGEMAKER_PROGRAM             = "inference.py"
      SAGEMAKER_REGION              = "us-west-2"
    }
  }
}

# SageMaker Endpoint Configuration
resource "aws_sagemaker_endpoint_configuration" "sagemaker_endpoint_config" {
  name = "sagemaker-endpoint-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.sagemaker_model.name
    initial_instance_count = 1
    instance_type          = "ml.m5.large"
  }
}

# SageMaker Endpoint
resource "aws_sagemaker_endpoint" "sagemaker_endpoint" {
  name = "sagemaker-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.sagemaker_endpoint_config.name
}

# Outputs
output "sagemaker_endpoint_name" {
  value = aws_sagemaker_endpoint.sagemaker_endpoint.name
}
