#!/bin/bash

# Colores
VERDE='\033[0;32m'
AZUL='\033[0;34m'
NC='\033[0m' 

echo -e "${AZUL}======================================================${NC}"
echo -e "${AZUL}        ASISTENTE DE INFRAESTRUCTURA OLLAMA IA        ${NC}"
echo -e "${AZUL}======================================================${NC}"
echo ""

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

echo ""
echo -e "${VERDE}==> Inyectando preferencias en terraform.tfvars...${NC}"

if [ ! -f "terraform.tfvars" ]; then
    echo "Error: No se encuentra el archivo terraform.tfvars en la raíz."
    exit 1
fi

sed -i "s/^ollama_instance_type.*/ollama_instance_type = \"$INST_OLLAMA\"/" terraform.tfvars
sed -i "s/^ollama_volume_size.*/ollama_volume_size   = $DISK_OLLAMA/" terraform.tfvars
sed -i "s/^ollama_model_name.*/ollama_model_name    = \"$MODEL_OLLAMA\"/" terraform.tfvars

# Limpiar saltos de línea invisibles de Windows por seguridad
sed -i 's/\r$//' terraform.tfvars

echo -e "${VERDE}¡Estructura de variables actualizada con éxito!${NC}"
echo -e "------------------------------------------------------"
echo -e " Servidor Ollama -> $INST_OLLAMA ($DISK_OLLAMA GB) [Model: $MODEL_OLLAMA]"
echo -e "------------------------------------------------------"
echo ""
echo -e "Ya puedes ejecutar ${VERDE}terraform apply${NC}."