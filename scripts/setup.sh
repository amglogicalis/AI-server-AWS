#!/bin/bash
# Redireccion limpia y segura de todos los logs a user-data.log
exec > /var/log/user-data.log 2>&1

echo "==> Iniciando aprovisionamiento dinamico de IA..."

# Variables inyectadas por Terraform en el despliegue
AI_MODE="${ai_hosting_mode}"
INSTANCE_TYPE="${aws_instance_type}"
MODEL_NAME="${ollama_model_name}"
API_KEY="${api_bridge_key}"
API_PROVIDER="${api_provider}"

# Desbloqueo agresivo de Ubuntu (La solucion comprobada)
echo "==> Limpiando bloqueos de apt/dpkg..."
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
dpkg --configure -a

echo "==> Instalando dependencias base..."
apt-get update -y
apt-get install -y curl python3 python3-pip python3-venv

# ---------------------------------------------------------------------
# MODO 1: OLLAMA LOCAL
# ---------------------------------------------------------------------
if [ "$AI_MODE" = "ollama" ]; then
    echo "==> MODO: Ollama Local"
    
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

# ---------------------------------------------------------------------
# MODO 2: API BRIDGE (PASARELA)
# ---------------------------------------------------------------------
elif [ "$AI_MODE" = "bridge" ]; then
    echo "==> MODO: API Bridge ($API_PROVIDER)"
    
    mkdir -p /opt/ai-bridge
    cd /opt/ai-bridge
    
    python3 -m venv .venv
    source .venv/bin/activate
    pip install fastapi uvicorn requests python-dotenv
    
    cat << 'EOF' > bridge.py
import os
import requests
from fastapi import FastAPI, HTTPException
from dotenv import load_dotenv

load_dotenv()
app = FastAPI(title="AI Terminal Bridge")

API_KEY = os.getenv("API_KEY")
MODEL_URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={API_KEY}"

@app.get("/ask")
def ask(prompt: str):
    if not prompt:
        raise HTTPException(status_code=400, detail="Falta el parametro prompt")
    
    payload = {"contents": [{"parts": [{"text": prompt}]}]}
    
    try:
        response = requests.post(MODEL_URL, json=payload, timeout=30)
        if response.status_code != 200:
            return {"error": f"Error de API externa: {response.text}"}
        
        data = response.json()
        respuesta_texto = data['candidates'][0]['content']['parts'][0]['text']
        return {"response": respuesta_texto}
    except Exception as e:
        return {"error": str(e)}
EOF

    echo "API_KEY=$API_KEY" > .env
    
    nohup uvicorn bridge:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
    echo "==> Servidor API Bridge listo y operativo."
fi