# Codex Alternativo Personal en AWS

> **Tu propio Codex/Claude Code en casa por $0.45/hora** usando GPU Spot de AWS, Terraform y Ollama.  
> El servidor solo corre cuando lo necesitas. Los modelos persisten en S3. Perfecto para workflows agenticos con [OpenCode](https://opencode.ai).

---

## ¿Qué es esto?

Esta infraestructura despliega un **servidor de IA local-en-la-nube** con:

- **GPU Spot** NVIDIA L4 24 GB (instancia `g6.2xlarge`) a ~$0.45/hora
- **Dos modelos Qwen2.5-Coder** para el workflow arquitecto+ejecutor
- **Ollama** como runtime de inferencia con API compatible con OpenAI
- **S3** para persistir los modelos entre encendidos (sin re-descargar)
- **Auto-restauración** de modelos al arrancar la instancia

### Arquitectura del workflow agentico

```
Tu tarea de código
       │
       ▼
┌─────────────────────────────┐
│  qwen-coder-72b  (Arquitecto)│  Q4_K_M · ~44 GB · ~1.5 tok/s
│  "Genera el plan en Markdown"│  Razona despacio pero con profundidad
└─────────────┬───────────────┘
              │ PLAN.md
              ▼
┌─────────────────────────────┐
│  qwen-coder-32b  (Ejecutor) │  Q4_K_M · ~18 GB · ~45 tok/s
│  "Implementa fase a fase"   │  Cabe 100% en VRAM → velocidad real
└─────────────────────────────┘
              │
              ▼
         OpenCode / Aider
```

---

## Comparativa de calidad vs alternativas comerciales

| Sistema | Modelo base | HumanEval | MBPP | Coste/hora | Privacidad |
|---|---|---|---|---|---|
| **GitHub Copilot / Codex** | GPT-4o | ~90% | ~87% | $0.13 (suscripción) | ❌ Cloud |
| **Antigravity / Claude Code** | Claude Sonnet 4 | ~92% | ~89% | ~$0.30-3.00 por tarea | ❌ Cloud |
| **Este setup (32B ejecutor)** | Qwen2.5-Coder-32B Q4_K_M | ~90% | ~86% | **$0.45/hora total** | ✅ Tu infra |
| **Este setup (72B arquitecto)** | Qwen2.5-72B Q4_K_M | ~94% | ~91% | incluido arriba | ✅ Tu infra |

> **Conclusión**: La calidad es prácticamente equivalente a los sistemas comerciales. Qwen2.5-Coder-32B Q4_K_M obtiene un 90% en HumanEval, a solo 2 puntos de GPT-4o. Para tareas reales de programación (refactoring, completar funciones, debugging), la diferencia es imperceptible.
>
> **Bonus**: AWS regala **$200 en créditos** para nuevas cuentas. Con este setup, eso son ~440 horas de GPU → meses de uso sin pagar nada.

---

## Prerrequisitos

| Herramienta | Versión mínima | Para qué |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5 | Desplegar la infra |
| [AWS CLI](https://aws.amazon.com/cli/) | >= 2.0 | Autenticación |
| Python | >= 3.9 | Scripts de mantenimiento |
| [OpenCode](https://opencode.ai) | última | Cliente agentico de IA |

### Cuenta AWS necesaria

- Región recomendada: **eu-central-1** (Frankfurt) — mejor disponibilidad de `g6.2xlarge` Spot
- Cuotas necesarias: `All G and VT Spot Instance Requests` ≥ 8 vCPUs  
  _(la `g6.2xlarge` usa 8 vCPUs)_
- Si tienes AWS Academy/Learner Lab: funciona directamente con `create_iam_resources = false`
- Si tienes cuenta personal: pon `create_iam_resources = true`

---

## Instalación paso a paso

### 1. Clonar y configurar credenciales

```bash
git clone <este-repo>
cd CAP
```

Configura tu perfil de AWS:
```bash
aws configure --profile personal
# AWS Access Key ID: TU_ACCESS_KEY
# AWS Secret Access Key: TU_SECRET_KEY
# Default region: eu-central-1
# Default output format: json
```

### 2. Crear tu `terraform.tfvars`

Copia el ejemplo y edita **solo los campos marcados**:

```bash
cp terraform.tfvars.example terraform.tfvars
```

**Campos obligatorios a cambiar:**

```hcl
aws_profile        = "personal"           # tu perfil de AWS CLI
aws_region         = "eu-central-1"       # región donde desplegar
aws_key_name       = "mi-keypair"         # nombre de tu Key Pair en AWS
s3_bucket_name     = "cap-ai-modelos-TUNOMBRE"  # nombre ÚNICO globalmente
budget_alert_email = "tu@email.com"       # email para alertas de coste
```

**Campos opcionales (ya tienen buenos defaults):**

```hcl
gpu_instance_type    = "g6.2xlarge"   # NVIDIA L4, $0.45/h Spot
gpu_root_volume_size = 120            # GB de EBS (modelos + SO)
use_spot             = true           # Spot = 75% más barato
budget_limit_usd     = "17.25"       # ~15 EUR de límite mensual
```

### 3. Añadir tu clave SSH

```bash
# Si ya tienes un Key Pair en AWS, pon su nombre en aws_key_name
# Si necesitas crear uno:
aws ec2 create-key-pair --key-name mi-keypair --profile personal \
  --query 'KeyMaterial' --output text > mi-keypair.pem
chmod 400 mi-keypair.pem
```

### 4. Desplegar

```bash
terraform init
terraform apply
```

La primera vez tarda ~20-25 minutos porque:
1. Crea bucket S3, IAM roles, Security Groups
2. Lanza una instancia bootstrap que descarga los modelos de HuggingFace (~62 GB) a S3
3. Lanza la GPU Spot que restaura los modelos desde S3 y arranca Ollama

**Las siguientes veces tarda ~5-8 minutos** (los modelos ya están en S3).

### 5. Verificar que funciona

```bash
# Obtener la IP del servidor
terraform output gpu_public_ip

# Test rápido
curl http://<IP>:11434/api/tags
```

Deberías ver los dos modelos: `qwen-coder-32b` y `qwen-coder-72b`.

---

## Uso con OpenCode (workflow recomendado)

[OpenCode](https://opencode.ai) es un cliente agentico de código que corre en terminal y soporta modelos locales via Ollama.

### Instalación de OpenCode

```bash
npm install -g opencode-ai
# o con bun:
bun install -g opencode-ai
```

### Configurar OpenCode con tu servidor

Crea o edita `~/.config/opencode/config.json`:

```json
{
  "providers": {
    "mi-servidor-ia": {
      "type": "ollama",
      "url": "http://<TU_IP>:11434"
    }
  },
  "model": "mi-servidor-ia/qwen-coder-32b"
}
```

O directamente en `.opencode.json` en la raíz de tu proyecto:

```json
{
  "model": "ollama/qwen-coder-32b",
  "ollama": {
    "host": "http://<TU_IP>:11434"
  }
}
```

### Workflow arquitecto + ejecutor

```bash
# FASE 1: Generar el plan de arquitectura con el 72B
opencode --model ollama/qwen-coder-72b \
  "Eres un arquitecto de software. Analiza este proyecto y genera un plan detallado en Markdown con fases de implementación, interfaces, y consideraciones técnicas."

# El plan se guarda en PLAN.md

# FASE 2: Ejecutar el plan fase a fase con el 32B
opencode --model ollama/qwen-coder-32b \
  "Implementa la Fase 1 del plan en PLAN.md. Escribe el código completo, los tests, y actualiza la documentación."
```

### Variables de entorno alternativa

```bash
export OPENCODE_MODEL="ollama/qwen-coder-32b"
export OLLAMA_HOST="http://<TU_IP>:11434"
opencode
```

---

## Gestión del servidor

### Encender/apagar para ahorrar

```bash
# Apagar cuando no uses (deja de cobrar GPU, solo paga EBS ~$10/mes)
python mantenimiento_server.py

# O directamente con AWS CLI
aws ec2 stop-instances --instance-ids <ID> --profile personal

# Encender
aws ec2 start-instances --instance-ids <ID> --profile personal
```

### Chat interactivo (sin OpenCode)

```bash
# Instala dependencias
pip install requests python-dotenv

# Edita .env con la IP de tu servidor (ya configurado por Terraform)
python chat.py
```

Comandos disponibles en el chat:
- `/model` — cambiar entre qwen-coder-32b y qwen-coder-72b
- `/clear` — limpiar contexto
- `/salir` — salir

### Destruir toda la infra

```bash
terraform destroy
```

> **Nota**: El bucket S3 con los modelos NO se destruye automáticamente (para evitar perder 62 GB de descarga). Bórralo manualmente si quieres:
> ```bash
> aws s3 rb s3://tu-bucket --force --profile personal
> ```

---

## Estructura del repositorio

```
CAP/
├── main.tf                    # Recursos AWS: EC2, S3, IAM, Security Groups, Budgets
├── variables.tf               # Todas las variables parametrizadas (sin hardcodeo)
├── outputs.tf                 # IPs, IDs y URLs de los recursos creados
├── terraform.tfvars           # TU configuración (no commitear al repo público)
├── terraform.tfvars.example   # Plantilla para nuevos usuarios
├── scripts/
│   ├── bootstrap.sh           # Descarga modelos de HuggingFace → S3 (instancia temporal)
│   └── gpu_setup.sh           # Instala drivers, Ollama, restaura modelos desde S3
├── chat.py                    # Cliente de chat interactivo con selección de modelo
├── mantenimiento_server.py    # GUI TUI para start/stop/terminate instancias
├── check_status.sh            # Monitor de estado durante terraform apply
└── .env                       # Variables de entorno locales (generado por Terraform)
```

---

## Personalización de modelos

Puedes usar **cualquier modelo GGUF de HuggingFace** editando `terraform.tfvars`:

```hcl
# Ejemplo: usar DeepSeek-Coder-V2 en vez de Qwen
model_32b_hf_repo     = "bartowski/DeepSeek-Coder-V2-Instruct-GGUF"
model_32b_hf_filename = "DeepSeek-Coder-V2-Instruct-Q4_K_M*.gguf"
model_32b_ollama_name = "deepseek-coder"

# Ejemplo: un solo modelo en vez de dos
model_72b_hf_repo     = ""  # Dejar vacío para no desplegar el 72B
```

---

## Estimación de costes

| Componente | Coste/mes (uso intensivo 4h/día) | Coste/mes (uso moderado 1h/día) |
|---|---|---|
| GPU Spot g6.2xlarge | ~$54 | ~$14 |
| EBS gp3 120 GB | ~$10 | ~$10 |
| S3 (~62 GB modelos) | ~$1.40 | ~$1.40 |
| Transferencia de datos | ~$0.50 | ~$0.10 |
| **Total** | **~$66/mes** | **~$26/mes** |

Con los **$200 de créditos AWS**: ~3 meses gratis de uso intensivo o ~7 meses de uso moderado.

---

## Solución de problemas

**La instancia GPU no arranca (InsufficientInstanceCapacity)**  
→ Prueba cambiar `gpu_subnet_id` a una AZ diferente o usa `use_spot = false` temporalmente.

**Ollama tarda mucho en responder la primera vez**  
→ Normal. La primera petición carga el modelo en VRAM (~30-60s). Las siguientes son inmediatas.

**El modelo responde muy lento (<5 tok/s)**  
→ Verifica que el modelo cabe en VRAM con `nvidia-smi`. Si ves CPU offloading masivo, es que el modelo es demasiado grande. Usa Q4_K_M en vez de Q8_0.

**Timeout en OpenCode**  
→ Aumenta el timeout en la config de OpenCode. El 72B puede tardar 2-3 min en respuestas largas.

**InsufficientInstanceCapacity para Spot**  
→ Prueba la región `eu-west-1` (Irlanda) como alternativa a Frankfurt.

---

## Licencia

MIT — úsalo, modifícalo, compártelo.
