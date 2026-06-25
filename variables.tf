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

variable "aws_key_name" {
  type        = string
  description = "El nombre de la llave SSH (Key Pair) en AWS"
  default     = "vockey" 
}

# --- CONFIGURACIÓN: OLLAMA ---
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
  description = "Modelo de Ollama a descargar"
  default     = "qwen2.5:7b"
}