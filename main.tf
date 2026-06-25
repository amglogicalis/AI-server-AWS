provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Grupo de Seguridad Exclusivo para Ollama y SSH
resource "aws_security_group" "ai_sg" {
  name        = "ai-host-ollama-security-group-v2"
  description = "Acceso SSH y puerto para Ollama"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ai-ollama-sg"
  }
}

# SERVIDOR ÚNICO: OLLAMA LOCAL
resource "aws_instance" "ollama_server" {
  ami           = var.aws_ami_id
  instance_type = var.ollama_instance_type
  key_name      = var.aws_key_name
  vpc_security_group_ids = [aws_security_group.ai_sg.id]

  root_block_device {
    volume_size           = var.ollama_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/setup.sh", {
    ollama_model_name = var.ollama_model_name
  })

  tags = {
    Name            = "ai-server-ollama"
    Mode            = "ollama"
    ModelOrProvider = var.ollama_model_name
  }
}

# AUTOMATIZACIÓN: Monitor de estado 
resource "null_resource" "auto_monitor" {
  triggers = {
    # Usamos el ID de la instancia como gatillo, que no cambia repentinamente
    instance_id = aws_instance.ollama_server.id
  }

  provisioner "local-exec" {
    # Le pasamos la IP real directamente al script
    command = "./check_status.sh ${aws_instance.ollama_server.public_ip}"
  }
}