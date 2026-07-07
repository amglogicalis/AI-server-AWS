# ============================================================
# variables.tf — Ollama GPU Server (Spot GPU + S3 + Wake/Sleep)
# Todas las variables están parametrizadas; nada está hardcodeado.
# ============================================================

# ------------------------------------------------------------
# PROVEEDOR AWS
# ------------------------------------------------------------
variable "aws_region" {
  type        = string
  description = "Región de AWS donde se despliega la infraestructura"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "Perfil de AWS configurado en ~/.aws/credentials"
  default     = "LearnerLab"
}


variable "aws_key_name" {
  type        = string
  description = "Nombre del Key Pair SSH en AWS"
  default     = "vockey"
}

# ------------------------------------------------------------
# IAM
# En AWS Academy Learner Lab existe un perfil de instancia
# predefinido llamado 'LabInstanceProfile' que usa el LabRole.
# Este rol tiene permisos de EC2 y S3 necesarios para la
# auto-terminación del bootstrap y acceso a los modelos.
# ------------------------------------------------------------
variable "iam_instance_profile_name" {
  type        = string
  description = "Nombre del Instance Profile IAM a adjuntar a las instancias EC2. En AWS Academy usar 'LabInstanceProfile'."
  default     = "LabInstanceProfile"
}

variable "create_iam_resources" {
  type        = bool
  description = "Si es true, Terraform creara el rol IAM y el Instance Profile para las instancias. Si es false (como en AWS Academy), se usara el perfil especificado en 'iam_instance_profile_name'."
  default     = false
}

# ------------------------------------------------------------
# S3 — ALMACÉN DE MODELOS GGUF
# El bucket persiste entre despliegues para evitar re-descargar
# los modelos (que pesan >75 GB en total).
# ------------------------------------------------------------
variable "s3_bucket_name" {
  type        = string
  description = "Nombre globalmente único del bucket S3 para almacenar los modelos GGUF. Ej: 'ollama-models-abc123'"
}

# ------------------------------------------------------------
# INSTANCIA BOOTSTRAP
# Instancia t3.medium que descarga los modelos de HuggingFace
# y los sube al bucket S3. Se auto-elimina al terminar.
# Solo se despliega si los modelos NO están ya en S3.
# ------------------------------------------------------------
variable "bootstrap_instance_type" {
  type        = string
  description = "Tipo de instancia EC2 para la tarea de descarga/subida de modelos (solo CPU, no necesita GPU)"
  default     = "t3.medium"
}

variable "bootstrap_volume_size" {
  type        = number
  description = "Tamaño del disco EBS gp3 en GB para la instancia bootstrap. Debe ser >= tamaño de UN modelo a la vez (~50 GB)."
  default     = 100
}

# ------------------------------------------------------------
# INSTANCIA GPU SPOT — SERVIDOR OLLAMA PRINCIPAL
# g6e.xlarge: NVIDIA L40S 48 GB VRAM, 4 vCPU, 32 GB RAM
#             + 250 GB NVMe SSD de instancia store (efímero)
# Los modelos se almacenan en el NVMe para evitar coste de EBS.
# Al apagarse la instancia, el NVMe se destruye (los modelos
# persisten en S3 y se re-descargan en el siguiente arranque).
# ------------------------------------------------------------
variable "gpu_instance_type" {
  type        = string
  description = "Tipo de instancia GPU Spot para el servidor Ollama. g6e.xlarge lleva NVIDIA L40S de 48 GB."
  default     = "g6e.xlarge"
}

variable "gpu_root_volume_size" {
  type        = number
  description = "Tamaño del disco raíz EBS gp3 en GB para la instancia GPU. Solo aloja el SO y binarios; los modelos van al NVMe."
  default     = 20
}

# ------------------------------------------------------------
# MODELO 72B — Qwen2.5-Coder-72B-Instruct Q4_K_M
# Cuantización de 4 bits, balance calidad/velocidad para 72B.
# Tamaño aproximado: ~42 GB (puede estar dividido en shards).
# ------------------------------------------------------------
variable "model_72b_hf_repo" {
  type        = string
  description = "Repositorio de HuggingFace del modelo de 72B"
  default     = "bartowski/Qwen2.5-72B-Instruct-GGUF"
}

variable "model_72b_hf_filename" {
  type        = string
  description = "Patrón glob para seleccionar los archivos GGUF del modelo 72B (soporta * para shards)"
  default     = "Qwen2.5-72B-Instruct-Q4_K_M*.gguf"
}

variable "model_72b_s3_prefix" {
  type        = string
  description = "Prefijo (carpeta) dentro del bucket S3 para los archivos del modelo 72B"
  default     = "models/72b/"
}

variable "model_72b_ollama_name" {
  type        = string
  description = "Nombre con el que el modelo de 72B se registrará en Ollama"
  default     = "qwen-coder-72b"
}

# ------------------------------------------------------------
# MODELO 32B — Qwen2.5-Coder-32B-Instruct Q4_K_M
# Cuantización de 4 bits: ~18 GB, cabe 100% en VRAM de la L4.
# Velocidad: ~45 tok/s. Calidad en benchmarks de código: ~90%
# vs ~92% del Q8_0. Diferencia imperceptible en la práctica.
# Perfecto como ejecutor en workflows agenticos (OpenCode, Aider).
# ------------------------------------------------------------
variable "model_32b_hf_repo" {
  type        = string
  description = "Repositorio de HuggingFace del modelo de 32B"
  default     = "bartowski/Qwen2.5-Coder-32B-Instruct-GGUF"
}

variable "model_32b_hf_filename" {
  type        = string
  description = "Patrón glob para seleccionar los archivos GGUF del modelo 32B (soporta * para shards)"
  default     = "Qwen2.5-Coder-32B-Instruct-Q4_K_M*.gguf"
}

variable "model_32b_s3_prefix" {
  type        = string
  description = "Prefijo (carpeta) dentro del bucket S3 para los archivos del modelo 32B"
  default     = "models/32b/"
}

variable "model_32b_ollama_name" {
  type        = string
  description = "Nombre con el que el modelo de 32B se registrará en Ollama"
  default     = "qwen-coder-32b"
}

# ------------------------------------------------------------
# AWS BUDGETS — ALERTAS DE COSTE MENSUAL
# Alerta de AVISO  (~10 EUR) y CRÍTICA (~15 EUR).
# Los umbrales se configuran como porcentaje del límite total.
# Conversión aproximada: 1 EUR ≈ 1.15 USD
#   10 EUR ≈ 11.50 USD → 67% de 17.25 USD
#   15 EUR ≈ 17.25 USD → 100% de 17.25 USD
# ------------------------------------------------------------
variable "budget_limit_usd" {
  type        = string
  description = "Límite mensual del presupuesto en USD. Valor por defecto: 17.25 USD ≈ 15 EUR."
  default     = "17.25"
}

variable "budget_warn_threshold_pct" {
  type        = number
  description = "Porcentaje del límite al que se envía la alerta de AVISO (gasto real). Por defecto 67% ≈ 10 EUR."
  default     = 67
}

variable "budget_alert_email" {
  type        = string
  description = "Dirección de correo electrónico para recibir las alertas de coste de AWS Budget"
}

# ------------------------------------------------------------
# COMPRA DE INSTANCIA: SPOT VS ON-DEMAND
# ------------------------------------------------------------
variable "use_spot" {
  type        = bool
  description = "Si es true, se solicitara la instancia GPU como Spot (mas barata pero sujeta a capacidad). Si es false, se creara como On-Demand (arranque garantizado)."
  default     = true
}

# ------------------------------------------------------------
# SUBRED (AVAILABILITY ZONE)
# ------------------------------------------------------------
variable "gpu_subnet_id" {
  type        = string
  description = "ID de la subred en AWS para la instancia GPU. Dejar vacio para seleccion automatica."
  default     = ""
}