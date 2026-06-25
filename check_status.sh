#!/bin/bash

# Colores para la terminal
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
ROJO='\033[0;31m'
NC='\033[0m' # Sin Color

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}    MONITOR DE DESPLIEGUE AUTOMÁTICO (LOCAL-EXEC)    ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

# 1. Leer los argumentos pasados directamente por Terraform
# $1 = IP de Ollama, $2 = IP del Bridge
OLLAMA_IP="${1:-DESACTIVADO}"
BRIDGE_IP="${2:-DESACTIVADO}"

# Formatear los Endpoints basados en los argumentos recibidos
if [ "$OLLAMA_IP" != "DESACTIVADO" ] && [ ! -z "$OLLAMA_IP" ]; then
    OLLAMA_ENDPOINT="http://${OLLAMA_IP}:11434"
else
    OLLAMA_ENDPOINT="DESACTIVADO"
fi

if [ "$BRIDGE_IP" != "DESACTIVADO" ] && [ ! -z "$BRIDGE_IP" ]; then
    BRIDGE_ENDPOINT="http://${BRIDGE_IP}:8000/ask"
else
    BRIDGE_ENDPOINT="DESACTIVADO"
fi

# Extraer el nombre del modelo configurado en tu tfvars
MODEL_NAME=$(grep "ollama_model_name" terraform.tfvars | cut -d'"' -f2)

# Animación de carga (Spinner)
SPIN="-\|/"
I=0

# --- VERIFICACIÓN DE OLLAMA ---
if [ "$OLLAMA_ENDPOINT" != "DESACTIVADO" ]; then
    echo -e "${CYAN}⏳ Servidor Ollama detectado en la IP: $OLLAMA_IP${NC}"
    echo -e " -> Fase 1: Levantando el motor de Ollama en AWS..."
    while true; do
        STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$OLLAMA_ENDPOINT/")
        if [ "$STATUS_CODE" == "200" ]; then
            echo -e "\r${VERDE}[OK] ¡El motor de Ollama ya está activo y escuchando!${NC}      "
            break
        fi
        I=$(( (I+1) % 4 ))
        printf "\r${AMARILLO}[${SPIN:$I:1}] Esperando apertura del puerto 11434...${NC}"
        sleep 3
    done

    echo -e " -> Fase 2: Comprobando la descarga del modelo '${MODEL_NAME}'..."
    while true; do
        MODEL_CHECK=$(curl -s --connect-timeout 2 "$OLLAMA_ENDPOINT/api/tags" | grep "$MODEL_NAME")
        if [ ! -z "$MODEL_CHECK" ]; then
            echo -e "\r${VERDE}[OK] ¡Modelo '${MODEL_NAME}' descargado completamente!${NC}      "
            break
        fi
        I=$(( (I+1) % 4 ))
        printf "\r${AMARILLO}[${SPIN:$I:1}] Descargando modelo en segundo plano dentro de AWS...${NC}"
        sleep 5
    done
    echo -e "${VERDE}🚀 ¡Tu servidor Ollama está listo! Puedes llamarlo en: $OLLAMA_ENDPOINT${NC}"
    echo ""
fi

# --- VERIFICACIÓN DEL API BRIDGE ---
if [ "$BRIDGE_ENDPOINT" != "DESACTIVADO" ]; then
    echo -e "${CYAN}⏳ Servidor API Bridge detectado en la IP: $BRIDGE_IP${NC}"
    
    while true; do
        STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$BRIDGE_ENDPOINT?prompt=ping")
        if [ "$STATUS_CODE" == "200" ]; then
            echo -e "\r${VERDE}[OK] ¡El servidor Bridge de Python ya está activo en el puerto 8000!${NC}      "
            break
        fi
        I=$(( (I+1) % 4 ))
        printf "\r${AMARILLO}[${SPIN:$I:1}] Esperando a que FastAPI configure el entorno virtual...${NC}"
        sleep 3
    done
    echo -e "${VERDE}🚀 ¡Tu pasarela hacia Gemini está lista! Puedes llamarla en: $BRIDGE_ENDPOINT${NC}"
    echo ""
fi

echo -e "${CYAN}======================================================${NC}"
echo -e "${VERDE}    ¡Flujo completado! Infraestructura operativa.     ${NC}"
echo -e "${CYAN}======================================================${NC}"