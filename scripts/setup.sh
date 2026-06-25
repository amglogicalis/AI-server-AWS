#!/bin/bash
exec > /var/log/user-data.log 2>&1

echo "==> Iniciando aprovisionamiento dinamico de IA (Ollama)..."

# Variable inyectada por Terraform
MODEL_NAME="${ollama_model_name}"

echo "==> Limpiando bloqueos de apt/dpkg..."
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
dpkg --configure -a

echo "==> Instalando dependencias base..."
apt-get update -y
apt-get install -y curl

echo "==> Instalando Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

echo "==> Aplicando override de IP (0.0.0.0)..."
mkdir -p /etc/systemd/system/ollama.service.d
echo '[Service]' > /etc/systemd/system/ollama.service.d/override.conf
echo 'Environment="OLLAMA_HOST=0.0.0.0"' >> /etc/systemd/system/ollama.service.d/override.conf

systemctl daemon-reload
systemctl restart ollama

sleep 5

echo "==> Descargando modelo: $MODEL_NAME..."
ollama pull "$MODEL_NAME"
echo "==> Servidor Ollama listo y operativo."