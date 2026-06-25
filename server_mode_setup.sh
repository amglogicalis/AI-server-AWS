#!/bin/bash

# Colores para una interfaz bonita en la terminal de WSL
VERDE='\033[0;32m'
AZUL='\033[0;34m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin Color

echo -e "${AZUL}======================================================${NC}"
echo -e "${AZUL}    ASISTENTE MULTI-SERVIDOR DE INFRAESTRUCTURA IA    ${NC}"
echo -e "${AZUL}======================================================${NC}"
echo ""

# --- COMPONENTE 1: OLLAMA ---
echo -e "${CYAN}¿Deseas activar el Servidor 1 (Ollama Local)?${NC}"
echo -e "Ejecuta modelos de IA por CPU/RAM dentro de tu servidor de AWS."
read -p "Activar? (y/n) [y]: " ACT_OLLAMA
ACT_OLLAMA=${ACT_OLLAMA:-y}

if [ "$ACT_OLLAMA" == "y" ] || [ "$ACT_OLLAMA" == "Y" ]; then
    DEPLOY_OLLAMA="true"
    echo -e " -> Tipo de instancia para Ollama (Recomendado: r5.large) "
    read -p "    Instancia [r5.large]: " INST_OLLAMA
    INST_OLLAMA=${INST_OLLAMA:-r5.large}
    
    echo -e " -> Disco EBS en GB (Recomendado: 50) "
    read -p "    Tamaño [50]: " DISK_OLLAMA
    DISK_OLLAMA=${DISK_OLLAMA:-50}
    
    echo -e " -> Selecciona el Modelo de IA para Ollama "
    echo -e "    1) qwen2.5:7b (Recomendado)"
    echo -e "    2) llama3.1:8b"
    echo -e "    3) phi3"
    read -p "    Selección (1-3) [1]: " MODEL_OPT
    if [ "$MODEL_OPT" == "2" ]; then MODEL_OLLAMA="llama3.1:8b"
    elif [ "$MODEL_OPT" == "3" ]; then MODEL_OLLAMA="phi3"
    else MODEL_OLLAMA="qwen2.5:7b"; fi
else
    DEPLOY_OLLAMA="false"
    INST_OLLAMA="r5.large"
    DISK_OLLAMA=50
    MODEL_OLLAMA="qwen2.5:7b"
fi

echo ""
# --- COMPONENTE 2: API BRIDGE ---
echo -e "${CYAN}¿Deseas activar el Servidor 2 (API Bridge para Gemini)?${NC}"
echo -e "Pasarela ligera que reenvía peticiones de forma remota usando tu API Key."
read -p "Activar? (y/n) [n]: " ACT_BRIDGE
ACT_BRIDGE=${ACT_BRIDGE:-n}

if [ "$ACT_BRIDGE" == "y" ] || [ "$ACT_BRIDGE" == "Y" ]; then
    DEPLOY_BRIDGE="true"
    echo -e " -> Tipo de instancia para Bridge (Recomendado: t3.micro) "
    read -p "    Instancia [t3.micro]: " INST_BRIDGE
    INST_BRIDGE=${INST_BRIDGE:-t3.micro}
    
    echo -e " -> Disco EBS en GB (Recomendado: 10) "
    read -p "    Tamaño [10]: " DISK_BRIDGE
    DISK_BRIDGE=${DISK_BRIDGE:-10}
else
    DEPLOY_BRIDGE="false"
    INST_BRIDGE="t3.micro"
    DISK_BRIDGE=10
fi

# --- ACTUALIZACIÓN DE TERRAFORM.TFVARS ---
echo ""
echo -e "${CYAN}==> Inyectando preferencias en terraform.tfvars...${NC}"

if [ ! -f "terraform.tfvars" ]; then
    echo "Error: No se encuentra el archivo terraform.tfvars en la raíz."
    exit 1
fi

# Modificar las líneas usando sed de Linux de forma segura
sed -i "s/^deploy_ollama.*/deploy_ollama   = $DEPLOY_OLLAMA/" terraform.tfvars
sed -i "s/^deploy_bridge.*/deploy_bridge   = $DEPLOY_BRIDGE/" terraform.tfvars
sed -i "s/^ollama_instance_type.*/ollama_instance_type = \"$INST_OLLAMA\"/" terraform.tfvars
sed -i "s/^ollama_volume_size.*/ollama_volume_size   = $DISK_OLLAMA/" terraform.tfvars
sed -i "s/^ollama_model_name.*/ollama_model_name = \"$MODEL_OLLAMA\"/" terraform.tfvars
sed -i "s/^bridge_instance_type.*/bridge_instance_type = \"$INST_BRIDGE\"/" terraform.tfvars
sed -i "s/^bridge_volume_size.*/bridge_volume_size   = $DISK_BRIDGE/" terraform.tfvars

# Limpiar saltos de línea invisibles de Windows por seguridad
sed -i 's/\r$//' terraform.tfvars

echo -e "${VERDE}¡Estructura de variables actualizada con éxito!${NC}"
echo -e "------------------------------------------------------"
echo -e " Servidor Ollama: [${AMARILLO}$DEPLOY_OLLAMA${NC}] -> $INST_OLLAMA ($DISK_OLLAMA GB) [Model: $MODEL_OLLAMA]"
echo -e " Servidor Bridge: [${AMARILLO}$DEPLOY_BRIDGE${NC}] -> $INST_BRIDGE ($DISK_BRIDGE GB)"
echo -e "------------------------------------------------------"
echo ""
echo -e "Ya puedes ejecutar ${VERDE}terraform plan${NC} o ${VERDE}terraform apply${NC}."