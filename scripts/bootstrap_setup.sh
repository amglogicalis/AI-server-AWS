#!/bin/bash
# =============================================================
# bootstrap_setup.sh
# Variables leidas desde env vars TF_* exportadas por user_data.
# IMPORTANTE: Este script usa SOLO $VAR sin llaves para variables
# bash, para evitar conflictos con la interpolacion de Terraform.
# =============================================================
exec > /var/log/user-data.log 2>&1

set -euo pipefail

# Leer variables de entorno inyectadas por Terraform
S3_BUCKET="$TF_S3_BUCKET"
AWS_REGION="$TF_AWS_REGION"
MODEL_72B_HF_REPO="$TF_MODEL_72B_HF_REPO"
MODEL_72B_HF_FILENAME="$TF_MODEL_72B_HF_FILENAME"
MODEL_72B_S3_PREFIX="$TF_MODEL_72B_S3_PREFIX"
MODEL_32B_HF_REPO="$TF_MODEL_32B_HF_REPO"
MODEL_32B_HF_FILENAME="$TF_MODEL_32B_HF_FILENAME"
MODEL_32B_S3_PREFIX="$TF_MODEL_32B_S3_PREFIX"

STAGING_BASE="/tmp/hf_staging"

echo "======================================================"
echo "[BOOTSTRAP] Iniciando descarga y subida de modelos"
echo "  S3 Bucket : s3://$S3_BUCKET"
echo "  Region    : $AWS_REGION"
echo "======================================================"

# ============================================================
# PASO 1: Instalacion de dependencias
# ============================================================
echo ""
echo "==> [1/4] Instalando dependencias del sistema..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -q
apt-get install -y -q awscli python3-pip python3-venv curl

echo "==> Instalando huggingface_hub..."
pip3 install --quiet --upgrade "huggingface_hub>=0.20.0"

# ============================================================
# PASO 2: Funcion de descarga y subida
# ============================================================
download_and_upload_model() {
    local hf_repo="$1"
    local hf_filename_pattern="$2"
    local s3_prefix="$3"
    local local_dir="$STAGING_BASE/$s3_prefix"

    mkdir -p "$local_dir"

    echo ""
    echo "------------------------------------------------------"
    echo "==> Descargando: $hf_repo ($hf_filename_pattern)"
    echo "    Destino: $local_dir"
    echo "------------------------------------------------------"

    python3 - <<PYEOF
import sys
from huggingface_hub import snapshot_download

try:
    path = snapshot_download(
        repo_id="$hf_repo",
        local_dir="$local_dir",
        allow_patterns=["$hf_filename_pattern"],
        local_dir_use_symlinks=False,
        ignore_patterns=["*.txt", "*.md", "*.json", "*.py", ".gitattributes", "*.yaml"],
    )
    print("==> Descarga completada en:", path)
except Exception as e:
    print("ERROR: Fallo en la descarga:", e, file=sys.stderr)
    sys.exit(1)
PYEOF

    echo "==> Subiendo a s3://$S3_BUCKET/$s3_prefix ..."
    aws s3 sync "$local_dir" "s3://$S3_BUCKET/$s3_prefix" \
        --region "$AWS_REGION" \
        --exclude "*.txt" \
        --exclude "*.md" \
        --exclude ".cache/*" \
        --exclude "*.json" \
        --exclude ".gitattributes"

    echo "==> Subida completada. Liberando espacio..."
    rm -rf "$local_dir"
    echo "==> Modelo procesado: s3://$S3_BUCKET/$s3_prefix"
}

# ============================================================
# PASO 3: Procesar modelos
# ============================================================
echo ""
echo "[2/4] MODELO 72B"
download_and_upload_model "$MODEL_72B_HF_REPO" "$MODEL_72B_HF_FILENAME" "$MODEL_72B_S3_PREFIX"

echo ""
echo "[3/4] MODELO 32B"
download_and_upload_model "$MODEL_32B_HF_REPO" "$MODEL_32B_HF_FILENAME" "$MODEL_32B_S3_PREFIX"

echo ""
echo "==> Ambos modelos en S3: s3://$S3_BUCKET/"

# ============================================================
# PASO 4: Auto-terminacion via IMDSv2
# ============================================================
echo ""
echo "[4/4] Auto-terminando instancia bootstrap..."

IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s \
    -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
    "http://169.254.169.254/latest/meta-data/instance-id")

echo "==> Terminando instancia: $INSTANCE_ID"

aws ec2 terminate-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION"

echo "======================================================"
echo " BOOTSTRAP COMPLETADO — Instancia se eliminara."
echo "======================================================"
