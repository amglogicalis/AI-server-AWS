#!/bin/bash
# =============================================================
# check_bootstrap_status.sh — Monitor local de subida a S3
#
# Uso: ./check_bootstrap_status.sh <BOOTSTRAP_IP> <KEY_NAME>
#
# Se conecta por SSH a la instancia bootstrap temporal y
# retransmite en tiempo real la descarga desde HuggingFace y
# la subida a S3 de los modelos.
# =============================================================

# Colores
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
ROJO='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

BOOTSTRAP_IP="${1}"
KEY_NAME="${2}"

if [ -z "$BOOTSTRAP_IP" ] || [ "$BOOTSTRAP_IP" == "" ]; then
    echo -e "${ROJO}Error: No se recibió una IP válida de la instancia bootstrap.${NC}"
    exit 1
fi

echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}   MONITOR DE BOOTSTRAP — DESCARGA Y SUBIDA A S3       ${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo ""
echo -e " ${CYAN}IP Bootstrap :${NC} $BOOTSTRAP_IP"
echo ""

# Buscar llave PEM
PEM_FILE=""
if [ -f "${KEY_NAME}.pem" ]; then
    PEM_FILE="${KEY_NAME}.pem"
elif [ -f "vockey.pem" ]; then
    PEM_FILE="vockey.pem"
fi

if [ -n "$PEM_FILE" ]; then
    echo -e " ${CYAN}[INFO] Llave SSH detectada: $PEM_FILE${NC}"
    echo -e " -> ${BOLD}Conectando por SSH a la instancia bootstrap para seguir la subida a S3...${NC}"
    echo -e "    (Esperando a que la máquina active el puerto SSH 22...)"

    # Esperar hasta 3 minutos a que responda el puerto 22
    for i in $(seq 1 60); do
        if nc -z -w 3 "$BOOTSTRAP_IP" 22 >/dev/null 2>&1 || bash -c "exec 3<>/dev/tcp/$BOOTSTRAP_IP/22" >/dev/null 2>&1; then
            break
        fi
        sleep 3
    done

    # Copiar la llave a /tmp para poder cambiarle los permisos a 400 en sistemas POSIX (como WSL o Git Bash)
    SAFE_PEM="/tmp/${KEY_NAME}_safe.pem"
    cp "$PEM_FILE" "$SAFE_PEM"
    chmod 400 "$SAFE_PEM"

    echo -e " ${VERDE}[OK] Conexión establecida. Retransmitiendo log de descarga y subida a S3...${NC}"
    echo -e "------------------------------------------------------------------------"

    if ssh -i "$SAFE_PEM" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=15 "ubuntu@$BOOTSTRAP_IP" '
        # Esperar a que se cree el archivo log
        for i in {1..30}; do
            if [ -f /var/log/user-data.log ]; then break; fi
            sleep 2
        done

        if [ ! -f /var/log/user-data.log ]; then
            echo "Error: No se encontró el log de arranque /var/log/user-data.log"
            exit 1
        fi

        # Iniciar tail en segundo plano
        tail -f -n 100 /var/log/user-data.log &
        TAIL_PID=$!

        # Monitorear hasta encontrar la marca de fin del bootstrap
        while true; do
            if grep -q "BOOTSTRAP COMPLETADO" /var/log/user-data.log 2>/dev/null; then
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
        echo -e " ${VERDE}[OK] Bootstrap finalizado con éxito. Los modelos ya están en S3.${NC}"
        rm -f "$SAFE_PEM"
    else
        echo -e "------------------------------------------------------------------------"
        echo -e " ${ROJO}[ERROR] Error en el streaming por SSH del bootstrap.${NC}"
        rm -f "$SAFE_PEM"
        exit 1
    fi
else
    echo -e " ${AMARILLO}[WARN] No se detectó archivo de llave PEM. Esperando 15 minutos en local...${NC}"
    sleep 900
fi

echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${VERDE} Proceso bootstrap completado. Iniciando creación del servidor GPU...${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"
