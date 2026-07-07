#!/bin/bash
# =============================================================
# check_status.sh — Monitor local del despliegue
#
# Uso: ./check_status.sh <OLLAMA_IP> <KEY_NAME> <MODELO_1> [MODELO_2] ...
#
# Se ejecuta en la máquina local (Terraform local-exec) y:
#   1. Si localiza la llave SSH (.pem), se conecta a la máquina
#      y transmite en tiempo real el log de instalación (drivers,
#      descargas de S3, etc.) para que el usuario vea el progreso.
#   2. Si no hay llave, hace polling HTTP al puerto 11434.
# =============================================================

# Colores
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
ROJO='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

OLLAMA_IP="${1}"
KEY_NAME="${2}"
shift 2
MODELS=("$@")

# Validación de argumentos
if [ -z "$OLLAMA_IP" ] || [ "$OLLAMA_IP" == "DESACTIVADO" ] || [ "$OLLAMA_IP" == "" ]; then
    echo -e "${ROJO}Error: No se recibió una IP válida del servidor Ollama.${NC}"
    exit 1
fi

OLLAMA_ENDPOINT="http://${OLLAMA_IP}:11434"
SPIN="-\\|/"
I=0

echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}   MONITOR DE DESPLIEGUE — SERVIDOR GPU SPOT          ${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo ""
echo -e " ${CYAN}Endpoint :${NC} $OLLAMA_ENDPOINT"
echo -e " ${CYAN}Modelos  :${NC} ${MODELS[*]}"
echo ""

# Buscar llave PEM para streaming por SSH
PEM_FILE=""
if [ -f "${KEY_NAME}.pem" ]; then
    PEM_FILE="${KEY_NAME}.pem"
elif [ -f "vockey.pem" ]; then
    PEM_FILE="vockey.pem"
fi

# ============================================================
# MODO SSH: Retransmitir logs remotos de instalación si la llave existe
# ============================================================
SSH_SUCCESS=false

if [ -n "$PEM_FILE" ]; then
    echo -e " ${CYAN}[INFO] Llave SSH detectada: $PEM_FILE${NC}"
    echo -e " -> ${BOLD}Intentando conexión SSH a la instancia para transmitir el progreso...${NC}"
    echo -e "    (Esperando a que la máquina active el puerto SSH 22...)"

    # Esperar hasta 3 minutos a que responda el puerto 22
    for i in $(seq 1 60); do
        if nc -z -w 3 "$OLLAMA_IP" 22 >/dev/null 2>&1 || bash -c "exec 3<>/dev/tcp/$OLLAMA_IP/22" >/dev/null 2>&1; then
            break
        fi
        sleep 3
    done

    # Copiar la llave a /tmp para poder cambiarle los permisos a 400 en sistemas POSIX (como WSL o Git Bash)
    SAFE_PEM="/tmp/${KEY_NAME}_safe.pem"
    cp "$PEM_FILE" "$SAFE_PEM"
    chmod 400 "$SAFE_PEM"

    # Conectar por SSH y hacer stream del log
    echo -e " ${VERDE}[OK] Puerto 22 abierto. Retransmitiendo log de instalación remota...${NC}"
    echo -e "------------------------------------------------------------------------"

    if ssh -i "$SAFE_PEM" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=15 "ubuntu@$OLLAMA_IP" '
        # Esperar a que se cree el archivo log
        for i in {1..30}; do
            if [ -f /var/log/user-data.log ]; then break; fi
            sleep 2
        done

        if [ ! -f /var/log/user-data.log ]; then
            echo "Error: No se encontro el log /var/log/user-data.log"
            exit 1
        fi

        # Iniciar tail en segundo plano
        tail -f -n 100 /var/log/user-data.log &
        TAIL_PID=$!

        # Monitorear hasta encontrar la marca de fin
        while true; do
            if grep -q "GPU SETUP COMPLETADO" /var/log/user-data.log 2>/dev/null; then
                sleep 2
                kill $TAIL_PID 2>/dev/null
                break
            fi
            if ! kill -0 $TAIL_PID 2>/dev/null; then
                tail -f -n 0 /var/log/user-data.log &
                TAIL_PID=$!
            fi
            sleep 3
        done
        wait $TAIL_PID 2>/dev/null
    '; then
        echo -e "------------------------------------------------------------------------"
        echo -e " ${VERDE}[OK] Instalación y configuración completadas en el servidor.${NC}"
        SSH_SUCCESS=true
        rm -f "$SAFE_PEM"
    else
        echo -e "------------------------------------------------------------------------"
        echo -e " ${AMARILLO}[WARN] Falló el streaming por SSH. Cambiando a monitor HTTP de respaldo...${NC}"
        rm -f "$SAFE_PEM"
    fi
fi

# ============================================================
# MODO POLLING HTTP (Backup o si no hay llave SSH)
# ============================================================
if [ "$SSH_SUCCESS" = false ]; then
    echo -e " -> ${BOLD}Monitoreo por HTTP:${NC} Esperando que el motor Ollama esté activo..."
    echo -e "    (Esto incluye instalación de drivers NVIDIA y descargas de modelos en la instancia)"

    while true; do
        STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$OLLAMA_ENDPOINT/" 2>/dev/null)
        if [ "$STATUS_CODE" == "200" ]; then
            echo -e "\r${VERDE}[OK] ¡Motor Ollama activo y escuchando en el puerto 11434!${NC}           "
            break
        fi
        I=$(( (I+1) % 4 ))
        printf "\r${AMARILLO}[${SPIN:$I:1}] Esperando puerto 11434 (drivers + modelos S3)...${NC}  "
        sleep 5
    done

    # Verificar disponibilidad de cada modelo individualmente
    for MODEL in "${MODELS[@]}"; do
        echo ""
        echo -e " -> Verificando disponibilidad del modelo '${CYAN}${MODEL}${NC}'..."
        while true; do
            MODEL_CHECK=$(curl -s --connect-timeout 3 "$OLLAMA_ENDPOINT/api/tags" 2>/dev/null | grep -i -o "$MODEL" | head -n 1 || true)
            if [ -n "$MODEL_CHECK" ]; then
                echo -e "\r${VERDE}[OK] ¡Modelo '${MODEL}' disponible en Ollama!${NC}           "
                break
            fi
            I=$(( (I+1) % 4 ))
            printf "\r${AMARILLO}[${SPIN:$I:1}] Esperando que el modelo '${MODEL}' se registre...${NC}  "
            sleep 5
        done
    done
fi

# ============================================================
# RESUMEN FINAL
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${VERDE}${BOLD} 🚀 ¡SERVIDOR OLLAMA GPU COMPLETAMENTE OPERATIVO!${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo ""
echo -e " ${BOLD}Endpoint API :${NC} $OLLAMA_ENDPOINT"
echo -e " ${BOLD}Modelos      :${NC}"
for MODEL in "${MODELS[@]}"; do
    echo -e "   ${VERDE}✓${NC} $MODEL"
done
echo ""
echo -e " Para chatear, actualiza ${BOLD}OLLAMA_URL${NC} en .env:"
echo -e "   OLLAMA_URL=${OLLAMA_ENDPOINT}/api/generate"
echo ""
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${VERDE} Infraestructura lista. ¡Flujo de despliegue completado!${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"