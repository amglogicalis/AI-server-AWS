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
echo "==> [4/5] Creando script de restauracion de NVMe (/usr/local/bin/ollama-nvme-restore.sh)...cat << EOF > /usr/local/bin/ollama-nvme-restore.sh
#!/bin/bash
# =============================================================
# Script autogenerado para restaurar modelos en el NVMe efímero
# en cada arranque de la instancia a partir de la librería Ollama en S3.
# =============================================================
exec >> /var/log/ollama-nvme-restore.log 2>&1
echo "=== [RESTORE START] \$(date) ==="

S3_BUCKET="$S3_BUCKET"
AWS_REGION="$AWS_REGION"

NVMe_MOUNT="$NVMe_MOUNT"
OLLAMA_MODELS_DIR="$OLLAMA_MODELS_DIR"

# 1. Detectar y montar NVMe si no está montado
echo "--> Detectando disco NVMe de instancia store..."
NVME_STORE=""
for nvme_candidate in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1; do
    if [ -b "\$nvme_candidate" ] && ! grep -q "^\$nvme_candidate" /proc/mounts 2>/dev/null; then
        NVME_STORE="\$nvme_candidate"
        break
    fi
done

if [ -n "\$NVME_STORE" ]; then
    echo "--> Montando disco efímero \$NVME_STORE en \$NVMe_MOUNT..."
    # Si no tiene sistema de archivos, formatear
    if ! blkid "\$NVME_STORE" >/dev/null 2>&1; then
        echo "--> Formateando \$NVME_STORE..."
        mkfs.ext4 -F "$NVME_STORE"
    fi
    mkdir -p "\$NVMe_MOUNT"
    mount "\$NVME_STORE" "\$NVMe_MOUNT"
    echo "--> Disco montado con éxito."
else
    echo "--> ADVERTENCIA: No se detectó disco NVMe vacío para montar."
    mkdir -p "\$NVMe_MOUNT"
fi

mkdir -p "\$OLLAMA_MODELS_DIR"
chmod 755 "\$NVMe_MOUNT" "\$OLLAMA_MODELS_DIR"

# Asegurar que Ollama esté detenido durante el restore
echo "--> Deteniendo Ollama..."
systemctl stop ollama

# 2. Sincronizar la librería de Ollama desde S3
echo "--> Sincronizando librería de Ollama desde S3..."
aws s3 sync "s3://\$S3_BUCKET/ollama/" "\$OLLAMA_MODELS_DIR/" --region "\$AWS_REGION"

# Si la carpeta de manifiestos está vacía, es una instalación inicial o se limpió S3
if [ ! -d "\$OLLAMA_MODELS_DIR/models/manifests" ] || [ -z "\$(ls -A \$OLLAMA_MODELS_DIR/models/manifests 2>/dev/null)" ]; then
    echo "--> S3 está vacío. Iniciando descarga directa de los modelos oficiales..."
    systemctl start ollama
    # Esperar a que Ollama responda
    for i in \$(seq 1 15); do
        if curl -s http://localhost:11434/ >/dev/null; then break; fi
        sleep 2
    done
    
    echo "--> Descargando qwen2.5-coder:32b..."
    OLLAMA_MODELS="\$OLLAMA_MODELS_DIR" ollama pull qwen2.5-coder:32b
    
    echo "--> Descargando qwen2.5:72b..."
    OLLAMA_MODELS="\$OLLAMA_MODELS_DIR" ollama pull qwen2.5:72b
    
    echo "--> Subiendo copia inicial a S3..."
    aws s3 sync "\$OLLAMA_MODELS_DIR/" "s3://\$S3_BUCKET/ollama/" --region "\$AWS_REGION"
    systemctl stop ollama
fi

# Asegurar permisos correctos para el usuario de ollama
chown -R ollama:ollama "\$OLLAMA_MODELS_DIR"

# 3. Arrancar Ollama al finalizar
echo "--> Iniciando servicio Ollama..."
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

# ============================================================
# PASO 6: Configurar auto-apagado de emergencia por inactividad (+8 horas)
# ============================================================
echo ""
echo "==> [6/6] Configurando script y cron de auto-apagado de emergencia..."

cat << 'EOF' > /usr/local/bin/auto-shutdown-check.sh
#!/bin/bash
# auto-shutdown-check.sh — Apaga la máquina si lleva más de 8 horas encendida.
UPTIME_SECONDS=$(cat /proc/uptime | awk '{print int($1)}')
LIMIT_SECONDS=28800 # 8 horas

if [ "$UPTIME_SECONDS" -gt "$LIMIT_SECONDS" ]; then
    echo "$(date): El servidor lleva encendido $UPTIME_SECONDS segundos (> 8 horas). Apagando de emergencia..." >> /var/log/auto-shutdown.log
    /sbin/shutdown -h now
fi
EOF

chmod +x /usr/local/bin/auto-shutdown-check.sh

# Configurar cron job para ejecutarse cada 15 minutos
cat << 'EOF' > /etc/cron.d/auto-shutdown
# Comprobar tiempo de actividad cada 15 minutos y apagar si supera las 8 horas
*/15 * * * * root /bin/bash /usr/local/bin/auto-shutdown-check.sh >/dev/null 2>&1
EOF

echo "==> Auto-apagado de emergencia configurado."

echo "======================================================"
echo " GPU SETUP CONFIGURADO CON ÉXITO"
echo " GPU SETUP COMPLETADO"
echo " El servicio de restauracion automatica se ejecutara en cada boot."
echo "======================================================"
