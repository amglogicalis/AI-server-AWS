# ============================================================
# main.tf — CAP AI Server (Spot GPU + S3 + Wake/Sleep)
#
# Arquitectura:
#   1. S3 Bucket  → almacén permanente de modelos GGUF (~76 GB)
#   2. Bootstrap  → t3.medium que descarga HuggingFace → sube S3
#                   Se autoeliminla. Solo se crea si los modelos
#                   NO están ya en S3 (verificado con data external).
#   3. GPU Spot   → g6e.xlarge con L40S, descarga modelos de S3
#                   al NVMe efímero y sirve Ollama multi-modelo.
#   4. Budget     → Alertas de coste a ~10 EUR y ~15 EUR.
# ============================================================

# ------------------------------------------------------------
# PROVEEDOR
# ------------------------------------------------------------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

provider "aws" {
  alias   = "s3_region"
  region  = "eu-west-1"
  profile = var.aws_profile
}

# ------------------------------------------------------------
# DATA SOURCE EXTERNO: Verificar si los modelos ya están en S3
#
# Ejecuta scripts/check_models_s3.py localmente (donde corre
# Terraform) usando el AWS CLI con el perfil configurado.
# Devuelve {"ready": "true"} si ambos prefijos tienen objetos.
# Si el bucket no existe o hay error de auth, devuelve "false".
#
# Comportamiento en despliegues posteriores:
#   - Modelos presentes en S3 → models_ready=true → bootstrap count=0
#   - Modelos ausentes         → models_ready=false → bootstrap count=1
# ------------------------------------------------------------
data "external" "models_status" {
  program = ["python", "${path.module}/scripts/check_models_s3.py"]

  query = {
    bucket      = var.s3_bucket_name
    prefix_72b  = var.model_72b_s3_prefix
    prefix_32b  = var.model_32b_s3_prefix
    aws_profile = var.aws_profile
    aws_region  = "eu-west-1"
  }
}

# ------------------------------------------------------------
# DATA SOURCE: AMI de Ubuntu 22.04 LTS (Canonical)
# Busca dinámicamente la última AMI oficial según la región.
# ------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------
# LOCALS
# ------------------------------------------------------------
locals {
  models_ready = data.external.models_status.result["ready"] == "true"

  common_tags = {
    Project     = "CAP-AI-Server"
    ManagedBy   = "Terraform"
    Environment = "learnerlab"
  }
}

# ------------------------------------------------------------
# GRUPO DE SEGURIDAD
# Abre SSH (22) y la API de Ollama (11434).
# Para producción, restringir cidr_blocks a tu IP pública.
# ------------------------------------------------------------
resource "aws_security_group" "ai_sg" {
  name        = "ai-server-sg-v3"
  description = "SSH (22) and Ollama API (11434) access"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Ollama REST API"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "ai-server-sg" })
}

# ------------------------------------------------------------
# S3 BUCKET: Almacén de modelos GGUF
# Se crea siempre (es idempotente y no tiene coste fijo).
# Permanece entre despliegues para no tener que re-descargar.
# ------------------------------------------------------------
resource "aws_s3_bucket" "models" {
  provider      = aws.s3_region
  bucket        = var.s3_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name    = var.s3_bucket_name
    Purpose = "gguf-model-storage"
  })
}

resource "aws_s3_bucket_public_access_block" "models" {
  provider = aws.s3_region
  bucket   = aws_s3_bucket.models.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "models" {
  provider = aws.s3_region
  bucket   = aws_s3_bucket.models.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }
  }
}

# ------------------------------------------------------------
# INSTANCIA BOOTSTRAP: Descarga modelos HF → Sube a S3 → Muere
#
# count = 0 si los modelos ya están en S3 (no se crea ni gasta).
# count = 1 en el primer despliegue o si los modelos faltan.
#
# User data: scripts/bootstrap_setup.sh (inyectado por templatefile)
# La instancia se autoeliminla al finalizar usando IMDSv2 +
# aws ec2 terminate-instances. Requiere el LabRole de AWS Academy.
# ------------------------------------------------------------
resource "aws_instance" "bootstrap" {
  count = local.models_ready ? 0 : 1

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.bootstrap_instance_type
  key_name               = var.aws_key_name
  vpc_security_group_ids      = [aws_security_group.ai_sg.id]
  iam_instance_profile        = var.create_iam_resources ? aws_iam_instance_profile.ai_profile[0].name : var.iam_instance_profile_name
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.bootstrap_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-USERDATA
#!/bin/bash
# --- Variables inyectadas por Terraform (valores de tfvars) ---
export TF_S3_BUCKET="${var.s3_bucket_name}"
export TF_AWS_REGION="eu-west-1"
export TF_MODEL_72B_HF_REPO="${var.model_72b_hf_repo}"
export TF_MODEL_72B_HF_FILENAME="${var.model_72b_hf_filename}"
export TF_MODEL_72B_S3_PREFIX="${var.model_72b_s3_prefix}"
export TF_MODEL_32B_HF_REPO="${var.model_32b_hf_repo}"
export TF_MODEL_32B_HF_FILENAME="${var.model_32b_hf_filename}"
export TF_MODEL_32B_S3_PREFIX="${var.model_32b_s3_prefix}"
# --- Ejecutar el script principal ---
${file("${path.module}/scripts/bootstrap_setup.sh")}
USERDATA

  tags = merge(local.common_tags, {
    Name          = "ai-bootstrap-uploader"
    Purpose       = "one-time-model-upload"
    AutoTerminate = "true"
  })

  # El bucket debe existir antes de que la instancia intente subir los modelos
  depends_on = [
    aws_s3_bucket.models,
    aws_s3_bucket_public_access_block.models,
  ]
}

# ------------------------------------------------------------
# ESPERA Y MONITOREO DE BOOTSTRAP (SUBIDA A S3)
# Se ejecuta si los modelos no están listos en S3.
# Fuerza a que el servidor GPU espere a que termine el bootstrap.
# ------------------------------------------------------------
resource "null_resource" "wait_for_bootstrap" {
  count = local.models_ready ? 0 : 1

  triggers = {
    bootstrap_instance_id = aws_instance.bootstrap[0].id
  }

  provisioner "local-exec" {
    command = "bash '${path.module}/check_bootstrap_status.sh' '${aws_instance.bootstrap[0].public_ip}' '${var.aws_key_name}'"
  }
}

# ------------------------------------------------------------
# INSTANCIA GPU SPOT: Servidor Ollama principal
#
# g6e.xlarge:
#   GPU   → 1x NVIDIA L40S (48 GB VRAM) — soporta 72B en GPU completa
#   CPU   → 4 vCPU, 32 GB RAM
#   Disco → 250 GB NVMe SSD de instancia store (EFÍMERO)
#   EBS   → 20 GB gp3 (solo SO y binarios)
#
# Diseño Wake/Sleep:
#   - Al apagar (stop):  NVMe destruido (modelos eliminados), EBS persiste.
#   - Al arrancar (start): user_data re-descarga modelos desde S3 al NVMe.
#   - Coste en reposo:   Solo el EBS de 20 GB (mínimo).
#
# NOTA: Las instancias Spot pueden ser interrumpidas por AWS con
# 2 min de aviso. Los modelos persisten en S3; no hay pérdida de datos.
# ------------------------------------------------------------
resource "aws_instance" "gpu_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.gpu_instance_type
  key_name               = var.aws_key_name
  vpc_security_group_ids      = [aws_security_group.ai_sg.id]
  iam_instance_profile        = var.create_iam_resources ? aws_iam_instance_profile.ai_profile[0].name : var.iam_instance_profile_name
  user_data_replace_on_change = true
  # subnet_id                   = var.gpu_subnet_id != "" ? var.gpu_subnet_id : null

  # Solicitud de instancia Spot (opcional / configurable)
  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        instance_interruption_behavior = "stop"
        spot_instance_type             = "persistent"
      }
    }
  }


  # Disco raíz mínimo: solo SO y binarios de Ollama
  root_block_device {
    volume_size           = var.gpu_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-USERDATA
#!/bin/bash
# --- Variables inyectadas por Terraform (valores de tfvars) ---
export TF_S3_BUCKET="${var.s3_bucket_name}"
export TF_AWS_REGION="eu-west-1"
export TF_MODEL_72B_S3_PREFIX="${var.model_72b_s3_prefix}"
export TF_MODEL_72B_NAME="${var.model_72b_ollama_name}"
export TF_MODEL_32B_S3_PREFIX="${var.model_32b_s3_prefix}"
export TF_MODEL_32B_NAME="${var.model_32b_ollama_name}"
# --- Ejecutar el script principal ---
${file("${path.module}/scripts/gpu_setup.sh")}
USERDATA

  tags = merge(local.common_tags, {
    Name   = "ai-server-ollama-gpu-spot"
    Mode   = "spot-gpu-l40s"
    Models = "${var.model_72b_ollama_name},${var.model_32b_ollama_name}"
  })

  depends_on = [
    null_resource.wait_for_bootstrap
  ]
}

# ------------------------------------------------------------
# MONITOR LOCAL: Espera a que el servidor Ollama esté listo
#
# Se ejecuta en la máquina local (donde corre Terraform) y
# hace polling al endpoint de Ollama hasta que:
#   1. El puerto 11434 responde HTTP 200.
#   2. Ambos modelos aparecen en /api/tags.
#
# Pasa la IP pública de la instancia GPU y los nombres de
# los modelos a check_status.sh.
# ------------------------------------------------------------
resource "null_resource" "monitor_gpu" {
  triggers = {
    instance_id = aws_instance.gpu_server.id
  }

  provisioner "local-exec" {
    command = "bash '${path.module}/check_status.sh' '${aws_instance.gpu_server.public_ip}' '${var.aws_key_name}' '${var.model_72b_ollama_name}' '${var.model_32b_ollama_name}'"
  }
}

# ------------------------------------------------------------
# AWS BUDGET: Alertas de coste mensual
#
# Alerta 1 — AVISO:    budget_warn_threshold_pct% del límite ≈ 10 EUR
#             Tipo: ACTUAL (gasto real acumulado en el mes).
# Alerta 2 — CRÍTICA:  100% del límite ≈ 15 EUR
#             Tipo: FORECASTED (previsión del gasto mensual total).
#
# NOTA: En AWS Academy Learner Lab, el servicio de Budgets puede
# estar restringido. Si terraform apply falla en este recurso,
# configurar el budget manualmente en la consola de AWS Billing.
# ------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "cap-ai-server-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alerta de AVISO: gasto real supera el umbral de advertencia (~10 EUR)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.budget_warn_threshold_pct
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Alerta CRÍTICA: previsión mensual supera el 100% del límite (~15 EUR)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# ------------------------------------------------------------
# RECURSOS IAM CONDICIONALES (Para cuenta personal)
# Se crean solo si var.create_iam_resources es true.
# ------------------------------------------------------------
resource "aws_iam_role" "ai_role" {
  count = var.create_iam_resources ? 1 : 0
  name  = "cap-ai-server-role-v3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Permisos para S3 (Lectura/Escritura para bootstrap y GPU)
resource "aws_iam_role_policy_attachment" "s3_access" {
  count      = var.create_iam_resources ? 1 : 0
  role       = aws_iam_role.ai_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Permisos para que la instancia bootstrap se auto-elimine
resource "aws_iam_role_policy" "ec2_terminate" {
  count = var.create_iam_resources ? 1 : 0
  name  = "ec2-terminate-policy"
  role  = aws_iam_role.ai_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ec2:TerminateInstances"
        Resource = "*"
      }
    ]
  })
}

# Perfil de instancia a adjuntar a EC2
resource "aws_iam_instance_profile" "ai_profile" {
  count = var.create_iam_resources ? 1 : 0
  name  = "cap-ai-server-instance-profile-v3"
  role  = aws_iam_role.ai_role[0].name
}