#!/bin/bash
# =============================================================
# server_mode_setup.sh — Asistente de configuración interactivo
#
# Configura terraform.tfvars con las preferencias del usuario:
#   - Nombre del bucket S3 (globalmente único)
#   - Tipo de instancia GPU Spot
#   - Email para alertas de coste (AWS Budget)
#
# Ejecutar ANTES de 'terraform apply' para configurar el entorno.
# =============================================================

VERDE='\033[0;32m'
AZUL='\033[0;34m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${AZUL}${BOLD}=====================================================${NC}"
echo -e "${AZUL}${BOLD}     ASISTENTE DE CONFIGURACIÓN — CAP AI SERVER      ${NC}"
echo -e "${AZUL}${BOLD}        Spot GPU + S3 + Wake/Sleep + Budget           ${NC}"
echo -e "${AZUL}${BOLD}=====================================================${NC}"
echo ""

# ============================================================
# 1. Nombre del Bucket S3
# ============================================================
TIMESTAMP_SUFFIX=$(date +%s | tail -c 8)
DEFAULT_BUCKET="cap-ai-models-${TIMESTAMP_SUFFIX}"

echo -e "${AMARILLO}[1] Nombre del bucket S3 (globalmente único en AWS):${NC}"
echo -e "    Solo minúsculas, números y guiones. Sin puntos ni mayúsculas."
read -rp "    Nombre [${DEFAULT_BUCKET}]: " S3_BUCKET_INPUT
S3_BUCKET="${S3_BUCKET_INPUT:-$DEFAULT_BUCKET}"

# Validar formato básico
if [[ ! "$S3_BUCKET" =~ ^[a-z0-9][a-z0-9-]{2,61}[a-z0-9]$ ]]; then
    echo -e "${AMARILLO}Advertencia: El nombre puede no cumplir las reglas de naming de S3.${NC}"
fi

# ============================================================
# 2. Tipo de instancia GPU Spot
# ============================================================
echo ""
echo -e "${AMARILLO}[2] Tipo de instancia GPU Spot para el servidor Ollama:${NC}"
echo -e "    ${CYAN}1)${NC} g6e.xlarge   → NVIDIA L40S 48 GB VRAM,  4 vCPU, 32 GB RAM  ${VERDE}[RECOMENDADO]${NC}"
echo -e "    ${CYAN}2)${NC} g6e.2xlarge  → NVIDIA L40S 48 GB VRAM,  8 vCPU, 64 GB RAM"
echo -e "    ${CYAN}3)${NC} g6e.4xlarge  → NVIDIA L40S 48 GB VRAM, 16 vCPU, 128 GB RAM"
echo -e "    ${CYAN}4)${NC} g6e.8xlarge  → NVIDIA L40S 48 GB VRAM, 32 vCPU, 256 GB RAM"
read -rp "    Selección (1-4) [1]: " GPU_OPT

case "${GPU_OPT}" in
    2) GPU_TYPE="g6e.2xlarge" ;;
    3) GPU_TYPE="g6e.4xlarge" ;;
    4) GPU_TYPE="g6e.8xlarge" ;;
    *) GPU_TYPE="g6e.xlarge" ;;
esac

# ============================================================
# 3. Email para alertas de presupuesto
# ============================================================
echo ""
echo -e "${AMARILLO}[3] Correo electrónico para alertas de coste AWS Budget:${NC}"
echo -e "    Recibirás avisos al llegar al ~10 EUR y ~15 EUR de gasto mensual."
read -rp "    Email: " BUDGET_EMAIL

if [ -z "$BUDGET_EMAIL" ]; then
    echo -e "${AMARILLO}Advertencia: No se especificó email. Usando placeholder.${NC}"
    BUDGET_EMAIL="sin-configurar@ejemplo.com"
fi

# ============================================================
# 4. Inyectar valores en terraform.tfvars
# ============================================================
TFVARS="terraform.tfvars"

if [ ! -f "$TFVARS" ]; then
    echo -e "${ROJO:-}Error: No se encuentra $TFVARS en el directorio actual.${NC}"
    exit 1
fi

echo ""
echo -e "${VERDE}==> Actualizando $TFVARS...${NC}"

# Actualizar S3 bucket name
sed -i "s|^s3_bucket_name.*|s3_bucket_name = \"$S3_BUCKET\"|" "$TFVARS"

# Actualizar tipo de instancia GPU
sed -i "s|^gpu_instance_type.*|gpu_instance_type = \"$GPU_TYPE\"|" "$TFVARS"

# Actualizar email de budget
sed -i "s|^budget_alert_email.*|budget_alert_email = \"$BUDGET_EMAIL\"|" "$TFVARS"

# Limpiar posibles caracteres Windows CR/LF
sed -i 's/\r$//' "$TFVARS"

echo -e "${VERDE}¡Configuración guardada correctamente!${NC}"
echo -e "-----------------------------------------------------"
echo -e " ${BOLD}S3 Bucket  ${NC}: $S3_BUCKET"
echo -e " ${BOLD}GPU Spot   ${NC}: $GPU_TYPE (NVIDIA L40S 48 GB VRAM)"
echo -e " ${BOLD}Budget     ${NC}: Alertas a ~10 EUR y ~15 EUR → $BUDGET_EMAIL"
echo -e "-----------------------------------------------------"
echo ""
echo -e "Próximos pasos:"
echo -e "  1. ${CYAN}terraform init${NC}    → (si aún no se ha hecho)"
echo -e "  2. ${CYAN}terraform plan${NC}    → Revisar qué se va a crear"
echo -e "  3. ${CYAN}terraform apply${NC}   → Desplegar la infraestructura"
echo ""
echo -e "${AZUL}Para apagar el servidor (Wake/Sleep):${NC}"
echo -e "  • Apagar Spot:  usa ${CYAN}python3 mantenimiento_server.py${NC}"
echo -e "  • Al volver a encender, los modelos se re-descargan desde S3."