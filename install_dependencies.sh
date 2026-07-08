#!/bin/bash
# install_dependencies.sh — Instala dependencias para Ollama AWS Server en Linux (Ubuntu/Debian) o macOS

echo "=================================================="
echo " CONFIGURADOR DE DEPENDENCIAS LOCALES (LINUX/MAC)"
echo "=================================================="

# Detectar SO
OS="$(uname -s)"

if [ "$OS" = "Linux" ]; then
    echo "--> Detectado Linux (Debian/Ubuntu)..."
    sudo apt update
    
    # Python 3
    if command -v python3 &>/dev/null; then
        echo "✅ Python 3 ya está instalado."
    else
        echo "--> Instalando Python 3..."
        sudo apt install -y python3 python3-pip python3-venv
    fi

    # AWS CLI
    if command -v aws &>/dev/null; then
        echo "✅ AWS CLI ya está instalado."
    else
        echo "--> Instalando AWS CLI..."
        sudo apt install -y awscli
    fi

    # Terraform
    if command -v terraform &>/dev/null; then
        echo "✅ Terraform ya está instalado."
    else
        echo "--> Instalando Terraform..."
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y terraform
    fi

elif [ "$OS" = "Darwin" ]; then
    echo "--> Detectado macOS (Homebrew)..."
    if ! command -v brew &>/dev/null; then
        echo "❌ Homebrew no instalado. Por favor instala Homebrew primero: https://brew.sh"
        exit 1
    fi
    
    brew install python awscli terraform
fi

# Instalar Aider
echo "--> Instalando/Actualizando Aider..."
python3 -m pip install -U pip
python3 -m pip install -U aider-chat

echo "=================================================="
echo " ¡INSTALACIÓN DE DEPENDENCIAS COMPLETADA!"
echo "=================================================="
