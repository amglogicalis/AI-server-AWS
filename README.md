# Personal AI Coding Server in AWS

> **Tu propio Copilot/Claude Code privado en la nube por $0.45/hora** usando GPU Spot de AWS, Terraform y Ollama.
> El servidor solo corre cuando lo necesitas. Los modelos persisten en tu bucket S3. Perfecto para workflows agénticos con [Aider](https://aider.chat).

---

## 🚀 Características principales

- **GPU Spot NVIDIA L4 24 GB** (instancia `g6.2xlarge`) a ~$0.45/hora.
- **Flujo 100% Autogestionado (Self-Bootstrapping)**: La primera vez que se enciende la máquina, descarga los modelos oficiales desde Ollama automáticamente y los sube a S3. En los siguientes arranques, los descarga de S3 en segundos. ¡No se necesita una instancia temporal "bootstrap"!
- **Modelos Oficiales Soportados por Defecto**:
  - `qwen2.5-coder:32b` (Ejecutor/Programador) - Cabe al 100% en la VRAM de la L4, ofreciendo velocidad máxima (~45-50 tokens/segundo) y calidad excelente.
  - `qwen2.5:72b` (Arquitecto/Razonamiento) - Para tareas de planificación compleja y arquitectura pesada.
- **Herramientas de Automatización Locales**:
  - `install_dependencies.ps1` / `install_dependencies.sh`: Instala todas las dependencias locales en tu PC con un solo comando.
  - `monitor_boot.py`: Enciende la máquina en AWS, muestra una barra de carga del progreso de la restauración de los modelos desde S3 y te devuelve el comando de Aider listo para copiar y pegar con la IP actual.
- **Auto-Apagado de Emergencia**: El servidor incluye un cronjob que monitoriza la actividad real y apaga automáticamente la máquina si lleva encendida más de 8 horas consecutivas, evitando gastos imprevistos.

---

## 🏗️ Arquitectura del Workflow Agéntico

```
Tu tarea de código
       │
       ▼
┌─────────────────────────────┐
│  qwen2.5:72b     (Arquitecto)│  Q4_K_M · ~47 GB · ~1.5 tok/s
│  "Genera el plan en Markdown"│  Razona despacio pero con profundidad
└─────────────┬───────────────┘
              │ PLAN.md
              ▼
┌─────────────────────────────┐
│  qwen2.5-coder:32b (Editor) │  Q4_K_M · ~19 GB · ~45 tok/s
│  "Implementa fase a fase"   │  Cabe 100% en VRAM → velocidad real
└─────────────────────────────┘
              │
              ▼
         Aider / IDE
```

---

## 📊 Comparativa de Calidad y Precios Reales

| Sistema | Modelo base | HumanEval (Coding) | Coste aproximado | Privacidad |
|---|---|---|---|---|
| **GitHub Copilot (Codex)** | GPT-4o / Codex custom | ~90.0% | $10.00 - $19.00 / mes | ❌ Cloud cerrado (Uso de datos) |
| **Claude Code / Antigravity** | Claude 3.5 Sonnet | **92.0%** | Dinámico por API (~$30 - $150/mes) | ❌ Cloud cerrado (Envía código) |
| **Este Setup (32B Editor)** | Qwen2.5-Coder-32B Q4 | **90.2%** | **$0.45 / hora activa** + ~$11.50/mes de almacenamiento | ✅ **100% Privado en tu AWS** |

---

## 🛠️ Prerrequisitos e Instalación

### 1. Instalar Dependencias Locales
Ejecuta el script configurador según tu sistema operativo para instalar automáticamente **AWS CLI**, **Python 3.12**, **Terraform** y **Aider**:

* **En Windows (PowerShell con Administrador):**
  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process -Force
  .\install_dependencies.ps1
  ```
* **En Linux/macOS:**
  ```bash
  chmod +x install_dependencies.sh
  ./install_dependencies.sh
  ```

### 2. Configurar credenciales de AWS
Configura tu perfil de AWS local:
```bash
aws configure --profile personal
# AWS Access Key ID: TU_ACCESS_KEY
# AWS Secret Access Key: TU_SECRET_KEY
# Default region: eu-central-1
# Default output format: json
```
> **Nota**: Se recomienda la región `eu-central-1` (Fráncfort) debido a la gran disponibilidad y bajo precio de las instancias L4 Spot.

### 3. Crear tu `terraform.tfvars`
Copia el archivo de ejemplo y configura tus valores personalizados (Keypair SSH, nombre único del bucket S3, etc.):
```bash
cp terraform.tfvars.example terraform.tfvars
```

---

## 🚀 Despliegue de la Infraestructura

Ejecuta el despliegue con Terraform:
```bash
terraform init
terraform apply
```
* **Tiempo de despliegue inicial**: ~5 minutos (AWS crea el S3, la red y la máquina GPU).
* Al arrancar por primera vez, el servidor detectará que tu S3 está vacío, descargará los modelos de Ollama de forma nativa en segundo plano y los guardará en tu S3 para futuros arranques.

---

## 🔌 Uso Diario (Workflow Automatizado)

Para simplificar tu día a día, utiliza el script monitor que enciende la máquina en AWS y te guía hasta iniciar Aider.

```bash
python monitor_boot.py
```

El script realizarás las siguientes acciones:
1. Enciende la instancia de AWS si estaba apagada.
2. Espera a que responda la red.
3. Lee el log del servidor y **muestra una barra de progreso en tiempo real** mientras descarga/restaura los modelos desde S3 al almacenamiento NVMe efímero de la GPU.
4. Genera el comando de inicio de Aider con la IP pública actual.

### Modo Single-Model (Solo 32B Coder)
Para programar de forma fluida y a alta velocidad (aconsejado para el 90% del trabajo diario):
```bash
aider --model openai/qwen2.5-coder:32b --openai-api-base http://<NUEVA_IP>:11434/v1
```

### Modo Dual-Model (Architect + Editor)
Para tareas muy complejas donde quieras que el modelo de 72B planifique los pasos y el de 32B modifique el código:
```bash
aider --model openai/qwen2.5:72b --editor-model openai/qwen2.5-coder:32b --openai-api-base http://<NUEVA_IP>:11434/v1
```

---

## 💾 Gestión de Costes y Auto-Apagado

- **Apagar el Servidor**: Cuando termines de trabajar, apaga el servidor para no incurrir en costes de GPU:
  ```bash
  aws ec2 stop-instances --instance-ids <TU_INSTANCE_ID> --profile personal
  ```
  *(Cuando el servidor está apagado, solo pagas por el disco EBS raíz y el almacenamiento S3, sumando unos ~$11.50/mes en total).*
- **Sistema de Seguridad**: Si olvidas apagar la máquina, el script de emergencia `/usr/local/bin/auto-shutdown-check.sh` detendrá el servidor automáticamente tras 8 horas continuadas de encendido.

---

## ⚙️ Personalización de Modelos

Puedes cambiar los modelos del servidor editando `variables.tf` o asignando los valores en `terraform.tfvars`. Ollama los descargará de forma automática en el arranque:
```hcl
# Ejemplo para usar modelos más pequeños o diferentes:
model_32b_ollama_name = "llama3.1:8b"
model_72b_ollama_name = "qwen2.5-coder:32b"
```

---

## 📄 Licencia
Este proyecto es de código abierto bajo la licencia MIT.
