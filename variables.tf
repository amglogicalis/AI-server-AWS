variable "aws_region" {
  type        = string
  description = "Región de AWS"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "El nombre del perfil de AWS configurado en tu archivo ~/.aws/credentials"
  default     = "LearnerLab"
}

variable "aws_ami_id" {
  type        = string
  description = "ID de la AMI del laboratorio"
}

# --- INTERRUPTORES DE DESPLIEGUE SIMULTÁNEO ---
variable "deploy_ollama" {
  type        = bool
  description = "¿Desplegar el servidor de Ollama Local? (true/false)"
  default     = true
}

variable "deploy_bridge" {
  type        = bool
  description = "¿Desplegar el servidor API Bridge de Gemini? (true/false)"
  default     = false
}

# --- CONFIGURACIÓN ESPECÍFICA: OLLAMA ---
variable "ollama_instance_type" {
  type        = string
  description = "Tipo de instancia EC2 para Ollama"
  default     = "r5.large"
}

variable "ollama_volume_size" {
  type        = number
  description = "Tamaño del disco EBS para Ollama"
  default     = 50
}

variable "ollama_model_name" {
  type        = string
  description = "Modelo de Ollama"
  default     = "qwen2.5:7b"
}

# --- CONFIGURACIÓN ESPECÍFICA: API BRIDGE ---
variable "bridge_instance_type" {
  type        = string
  description = "Tipo de instancia EC2 para el Bridge"
  default     = "t3.micro"
}

variable "bridge_volume_size" {
  type        = number
  description = "Tamaño del disco EBS para el Bridge"
  default     = 10
}

variable "api_bridge_key" {
  type        = string
  description = "API Key externa"
  sensitive   = true
}

variable "api_provider" {
  type        = string
  description = "Proveedor cloud de la API"
  default     = "gemini"
}

variable "aws_key_name" {
  type        = string
  description = "El nombre de la llave SSH (Key Pair) en AWS"
  default     = "vockey" # Dejamos vockey por defecto porque es el estándar del Learner Lab
}