# ============================================================
# outputs.tf — Ollama GPU Server (Spot GPU + S3 + Wake/Sleep)
# ============================================================

output "gpu_server_public_ip" {
  value       = aws_instance.gpu_server.public_ip
  description = "IP pública del servidor GPU Spot con Ollama"
}

output "endpoint_ollama" {
  value       = "http://${aws_instance.gpu_server.public_ip}:11434"
  description = "URL base del endpoint Ollama API (usar para chat.py y otras herramientas)"
}

output "s3_models_bucket" {
  value       = aws_s3_bucket.models.bucket
  description = "Nombre del bucket S3 donde se almacenan los modelos GGUF"
}

output "s3_models_bucket_arn" {
  value       = aws_s3_bucket.models.arn
  description = "ARN del bucket S3 de modelos"
}

output "models_ready_in_s3" {
  value       = local.models_ready
  description = "true si ambos modelos ya están en S3 y el bootstrap fue omitido"
}

output "bootstrap_status" {
  value       = local.models_ready ? "OMITIDO — modelos ya presentes en S3" : "DESPLEGADO — subiendo modelos a S3 (se auto-eliminará al terminar)"
  description = "Estado de la instancia bootstrap en este despliegue"
}

output "modelos_disponibles" {
  value = {
    modelo_72b = var.model_72b_ollama_name
    modelo_32b = var.model_32b_ollama_name
  }
  description = "Nombres de los modelos registrados en Ollama"
}