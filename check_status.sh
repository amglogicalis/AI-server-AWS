#!/bin/bash

# Colores para la terminal
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' 

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}    MONITOR DE DESPLIEGUE AUTOMÁTICO (LOCAL-EXEC)    ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

OLLAMA_IP="${1}"

if [ -z "$OLLAMA_IP" ] || [ "$OLLAMA_IP" == "DESACTIVADO" ]; then
    echo "Error: No se recibió la IP de Ollama válida."
    exit 1
fi

OLLAMA_ENDPOINT="http://${OLLAMA_IP}:11434"
MODEL_NAME=$(grep "ollama_model_name" terraform.tfvars | cut -d'"' -f2)

SPIN="-\|/"
I=0

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
echo -e "${CYAN}======================================================${NC}"
echo -e "${VERDE}    ¡Flujo completado! Infraestructura operativa.     ${NC}"
echo -e "${CYAN}======================================================${NC}"