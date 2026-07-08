# install_dependencies.ps1 — Instala dependencias para Ollama AWS Server en Windows

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " CONFIGURADOR DE DEPENDENCIAS LOCALES (WINDOWS)   " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Verificar/Instalar Python 3.12
if (Get-Command python -ErrorAction SilentlyContinue) {
    $version = python --version
    Write-Host "✅ Python ya está instalado: $version" -ForegroundColor Green
} else {
    Write-Host "--> Instalando Python 3.12 vía Winget..." -ForegroundColor Yellow
    winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    Write-Host "⚠️ Por favor, reinicia tu terminal después de esta instalación." -ForegroundColor Yellow
}

# 2. Verificar/Instalar AWS CLI
if (Get-Command aws -ErrorAction SilentlyContinue) {
    Write-Host "✅ AWS CLI ya está instalado." -ForegroundColor Green
} else {
    Write-Host "--> Instalando AWS CLI vía Winget..." -ForegroundColor Yellow
    winget install --id Amazon.AWSCLI --silent --accept-package-agreements --accept-source-agreements
}

# 3. Verificar/Instalar Terraform
if (Get-Command terraform -ErrorAction SilentlyContinue) {
    Write-Host "✅ Terraform ya está instalado." -ForegroundColor Green
} else {
    Write-Host "--> Instalando Terraform vía Winget..." -ForegroundColor Yellow
    winget install --id HashiCorp.Terraform --silent --accept-package-agreements --accept-source-agreements
}

# 4. Instalar Aider
Write-Host "--> Instalando/Actualizando Aider vía Pip..." -ForegroundColor Yellow
python -m pip install -U pip
python -m pip install -U aider-chat

if (Get-Command aider -ErrorAction SilentlyContinue) {
    Write-Host "✅ Aider instalado con éxito." -ForegroundColor Green
} else {
    Write-Host "⚠️ Aider se instaló pero puede requerir reiniciar la terminal para estar en el PATH." -ForegroundColor Yellow
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " ¡INSTALACIÓN DE DEPENDENCIAS COMPLETADA!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
