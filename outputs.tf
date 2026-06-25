output "ollama_ip_publica" {
  value       = var.deploy_ollama ? aws_instance.ollama_server[0].public_ip : "DESACTIVADO"
  description = "IP pública del servidor Ollama"
}

output "endpoint_ollama" {
  value       = var.deploy_ollama ? "http://${aws_instance.ollama_server[0].public_ip}:11434" : "DESACTIVADO"
  description = "URL para invocar a Ollama"
}

output "bridge_ip_publica" {
  value       = var.deploy_bridge ? aws_instance.bridge_server[0].public_ip : "DESACTIVADO"
  description = "IP pública del servidor API Bridge"
}

output "endpoint_bridge" {
  value       = var.deploy_bridge ? "http://${aws_instance.bridge_server[0].public_ip}:8000/ask" : "DESACTIVADO"
  description = "URL para invocar a la pasarela Gemini"
}