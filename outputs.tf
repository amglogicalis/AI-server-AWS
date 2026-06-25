output "ollama_ip_publica" {
  value       = aws_instance.ollama_server.public_ip
  description = "IP pública del servidor Ollama"
}

output "endpoint_ollama" {
  value       = "http://${aws_instance.ollama_server.public_ip}:11434"
  description = "URL para invocar a Ollama"
}