#!/bin/bash
# =============================================================
# gpu_setup.sh — Servidor Ollama GPU Spot (g6e.xlarge / L40S)
#
# Las variables de Terraform se pasan como variables de entorno
# con prefijo TF_ desde el bloque user_data de main.tf.
#
# Este script se ejecuta en el PRIMER arranque de la instancia.
# Instala drivers, Ollama, y configura un servicio de systemd
# permanente para restaurar el disco NVMe efímero en CADA inicio.
# =============================================================
exec > /var/log/user-data.log 2>&1

set -uo pipefail

# --- Leer variables de entorno inyectadas por Terraform ---
S3_BUCKET="$TF_S3_BUCKET"
AWS_REGION="$TF_AWS_REGION"
MODEL_72B_S3_PREFIX="$TF_MODEL_72B_S3_PREFIX"
MODEL_72B_NAME="$TF_MODEL_72B_NAME"
MODEL_32B_S3_PREFIX="$TF_MODEL_32B_S3_PREFIX"
MODEL_32B_NAME="$TF_MODEL_32B_NAME"

NVMe_MOUNT="/mnt/nvme"
OLLAMA_MODELS_DIR="$NVMe_MOUNT/ollama"
STAGING_DIR="$NVMe_MOUNT/staging"

echo "======================================================"
echo "[GPU SETUP] Iniciando configuracion y aprovisionamiento"
echo "  S3 Bucket  : s3://$S3_BUCKET"
echo "  Region     : $AWS_REGION"
echo "  Modelo 72B : $MODEL_72B_NAME"
echo "  Modelo 32B : $MODEL_32B_NAME"
echo "======================================================"

# ============================================================
# PASO 1: Dependencias del sistema
# ============================================================
echo ""
echo "==> [1/5] Instalando dependencias de red y disco..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -q
apt-get install -y -q \
    curl \
    awscli \
    nvme-cli \
    parted \
    util-linux \
    software-properties-common \
    pciutils

# ============================================================
# PASO 2: Instalacion de drivers NVIDIA
# ============================================================
echo ""
echo "==> [2/5] Instalando drivers NVIDIA..."

if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
    echo "==> Drivers NVIDIA ya detectados."
else
    add-apt-repository -y ppa:graphics-drivers/ppa 2>/dev/null || true
    apt-get update -y -q

    echo "==> Instalando nvidia-driver-550-server..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-550-server 2>&1 || {
        echo "==> Fallo nvidia-driver-550-server. Ejecutando ubuntu-drivers autoinstall..."
        ubuntu-drivers autoinstall 2>&1 || {
            echo "==> ubuntu-drivers fallo. Intentando nvidia-driver-535-server..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-535-server 2>&1 || true
        }
    }

    modprobe nvidia 2>/dev/null || echo "==> Nota: modulo nvidia cargara tras reinicio."
fi

# ============================================================
# PASO 3: Instalacion y configuracion de Ollama
# ============================================================
echo ""
echo "==> [3/5] Instalando Ollama..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi

echo "==> Configurando variables de entorno de Ollama..."
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_MODELS=$OLLAMA_MODELS_DIR"
Environment="OLLAMA_NUM_GPU=1"
EOF

systemctl daemon-reload
systemctl enable ollama
echo "==> Servicio Ollama configurado."

# ============================================================
# PASO 4: Crear el script de restauracion de NVMe en cada boot
# ============================================================
echo ""
echo "==> [4/5] Creando script de restauracion de NVMe (/usr/local/bin/ollama-nvme-restore.sh)..."

cat << EOF > /usr/local/bin/ollama-nvme-restore.sh
#!/bin/bash
# =============================================================
# Script autogenerado para restaurar modelos en el NVMe efímero
# en cada arranque de la instancia.
# =============================================================
exec >> /var/log/ollama-nvme-restore.log 2>&1
echo "=== [RESTORE START] \$(date) ==="

S3_BUCKET="$S3_BUCKET"
AWS_REGION="$AWS_REGION"
MODEL_72B_S3_PREFIX="$MODEL_72B_S3_PREFIX"
MODEL_72B_NAME="$MODEL_72B_NAME"
MODEL_32B_S3_PREFIX="$MODEL_32B_S3_PREFIX"
MODEL_32B_NAME="$MODEL_32B_NAME"

NVMe_MOUNT="$NVMe_MOUNT"
OLLAMA_MODELS_DIR="$OLLAMA_MODELS_DIR"
STAGING_DIR="$STAGING_DIR"

# 1. Detectar y montar NVMe si no esta montado
echo "--> Detectando disco NVMe de instancia store..."
NVME_STORE=""
for nvme_candidate in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1; do
    if [ -b "\$nvme_candidate" ] && ! grep -q "^\$nvme_candidate" /proc/mounts 2>/dev/null; then
        NVME_STORE="\$nvme_candidate"
        break
    fi
done

if [ -n "\$NVME_STORE" ]; then
    echo "--> Montando disco efimero \$NVME_STORE en \$NVMe_MOUNT..."
    # Si no tiene sistema de archivos, formatear
    if ! blkid "\$NVME_STORE" >/dev/null 2>&1; then
        echo "--> Formateando \$NVME_STORE..."
        mkfs.ext4 -F "\$NVME_STORE"
    fi
    mkdir -p "\$NVMe_MOUNT"
    mount "\$NVME_STORE" "\$NVMe_MOUNT"
    echo "--> Disco montado con exito."
else
    echo "--> ADVERTENCIA: No se detecto disco NVMe vacio para montar."
    mkdir -p "\$NVMe_MOUNT"
fi

mkdir -p "\$OLLAMA_MODELS_DIR" "\$STAGING_DIR"
chmod 755 "\$NVMe_MOUNT" "\$OLLAMA_MODELS_DIR" "\$STAGING_DIR"
chown -R ollama:ollama "\$OLLAMA_MODELS_DIR"

# Asegurar que Ollama este detenido durante el restore
systemctl stop ollama

# 2. Descargar y registrar modelos desde S3
register_model() {
    local m_name="\$1"
    local m_s3_prefix="\$2"
    local m_staging="\$STAGING_DIR/\$m_name"

    # Verificar si el modelo ya esta registrado (por si no se limpio el NVMe)
    if [ -d "\$OLLAMA_MODELS_DIR/manifests/registry.ollama.ai/library/\$m_name" ]; then
        echo "--> Modelo \$m_name ya registrado. Saltando descarga."
        return 0
    fi

    echo "--> Sincronizando \$m_name desde S3..."
    mkdir -p "\$m_staging"
    aws s3 sync "s3://\$S3_BUCKET/\$m_s3_prefix" "\$m_staging/" --region "\$AWS_REGION"

    local gguf_file
    gguf_file=\$(find "\$m_staging" -name "*.gguf" | sort | head -1)

    if [ -z "\$gguf_file" ]; then
        echo "--> ERROR: No GGUF found for \$m_name"
        return 1
    fi

    local mf="/tmp/Modelfile_\$m_name"
    cat > "\$mf" <<MEOF
FROM \$gguf_file
TEMPLATE """{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{- else if .Tools }}<|im_start|>system
# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{{- range .Tools }}
{"type": "function", "function": {{ .Function }}}
{{- end }}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call><|im_end|>
{{- end }}
{{- range .Messages }}
{{- if eq .Role "user" }}<|im_start|>user
{{ .Content }}<|im_end|>
{{- else if eq .Role "assistant" }}<|im_start|>assistant
{{- if .Content }}
{{ .Content }}
{{- end }}
{{- if .ToolCalls }}<|im_start|>call
{{- range .ToolCalls }}
{"name": "{{ .Function.Name }}", "arguments": {{ .Function.Arguments }}}
{{- end }}<|im_end|>
{{- end }}<|im_end|>
{{- else if eq .Role "tool" }}<|im_start|>user
<tool_response>
{{ .Content }}
</tool_response><|im_end|>
{{- end }}
{{- end }}<|im_start|>assistant
"""
PARAMETER stop <|im_start|>
PARAMETER stop <|im_end|>
PARAMETER num_ctx 16384
MEOF

    # Iniciar Ollama temporalmente para poder registrar el modelo
    systemctl start ollama
    # Esperar a que Ollama responda
    for i in \$(seq 1 15); do
        if curl -s http://localhost:11434/ >/dev/null; then break; fi
        sleep 2
    done

    OLLAMA_MODELS="\$OLLAMA_MODELS_DIR" ollama create "\$m_name" -f "\$mf"
    systemctl stop ollama

    rm -f "\$mf"
    rm -rf "\$m_staging"
}

register_model "\$MODEL_72B_NAME" "\$MODEL_72B_S3_PREFIX"
register_model "\$MODEL_32B_NAME" "\$MODEL_32B_S3_PREFIX"

rmdir "\$STAGING_DIR" 2>/dev/null || true

# 3. Arrancar Ollama al finalizar
echo "--> Iniciando servicio Ollama permanente..."
systemctl start ollama

echo "=== [RESTORE END] \$(date) ==="
EOF

chmod +x /usr/local/bin/ollama-nvme-restore.sh

# ============================================================
# PASO 5: Configurar y habilitar el servicio systemd
# ============================================================
echo ""
echo "==> [5/5] Configurando systemd unit (ollama-nvme-restore.service)..."

cat << 'EOF' > /etc/systemd/system/ollama-nvme-restore.service
[Unit]
Description=Restaurar modelos en disco NVMe efimero de Ollama
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ollama-nvme-restore.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ollama-nvme-restore.service

# Ejecutar la primera restauracion de forma inmediata
echo "==> Ejecutando primera sincronizacion de modelos..."
systemctl start ollama-nvme-restore.service

echo "======================================================"
echo " GPU SETUP CONFIGURADO CON ÉXITO"
echo " GPU SETUP COMPLETADO"
echo " El servicio de restauracion automatica se ejecutara en cada boot."
echo "======================================================"
