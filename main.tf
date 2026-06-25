provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Grupo de Seguridad Multi-Puerto (Abierto para SSH, Ollama y FastAPI)
resource "aws_security_group" "ai_sg" {
  name        = "ai-host-multi-security-group"
  description = "Acceso SSH y puertos para Ollama y API Bridge simultaneos"

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

  ingress {
    from_port   = 8000
    to_port     = 8000
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
    Name = "ai-multi-sg"
  }
}

# SERVIDOR 1: OLLAMA LOCAL
resource "aws_instance" "ollama_server" {
  count         = var.deploy_ollama ? 1 : 0
  ami           = var.aws_ami_id
  instance_type = var.ollama_instance_type
  key_name      = var.aws_key_name # <--- ¡Llave SSH vinculada por variable!
  
  vpc_security_group_ids = [aws_security_group.ai_sg.id]

  root_block_device {
    volume_size           = var.ollama_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/setup.sh", {
    ai_hosting_mode   = "ollama"
    aws_instance_type = var.ollama_instance_type
    ollama_model_name = var.ollama_model_name
    api_bridge_key    = ""
    api_provider      = ""
  })

  tags = {
    Name            = "ai-server-ollama"
    Mode            = "ollama"
    ModelOrProvider = var.ollama_model_name
  }
}

# SERVIDOR 2: API BRIDGE
resource "aws_instance" "bridge_server" {
  count         = var.deploy_bridge ? 1 : 0
  ami           = var.aws_ami_id
  instance_type = var.bridge_instance_type
  key_name      = var.aws_key_name # <--- ¡Llave SSH vinculada por variable!
  
  vpc_security_group_ids = [aws_security_group.ai_sg.id]

  root_block_device {
    volume_size           = var.bridge_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/setup.sh", {
    ai_hosting_mode   = "bridge"
    aws_instance_type = var.bridge_instance_type
    ollama_model_name = ""
    api_bridge_key    = var.api_bridge_key
    api_provider      = var.api_provider
  })

  tags = {
    Name            = "ai-server-bridge"
    Mode            = "bridge"
    ModelOrProvider = var.api_provider
  }
}

# AUTOMATIZACIÓN: Lanzar el monitor de estado automáticamente al terminar el apply
resource "null_resource" "auto_monitor" {
  depends_on = [
    aws_instance.ollama_server,
    aws_instance.bridge_server
  ]

  triggers = {
    ollama_ip = var.deploy_ollama ? aws_instance.ollama_server[0].public_ip : "DESACTIVADO"
    bridge_ip = var.deploy_bridge ? aws_instance.bridge_server[0].public_ip : "DESACTIVADO"
  }

  provisioner "local-exec" {
    command = "./check_status.sh ${self.triggers.ollama_ip} ${self.triggers.bridge_ip}"
  }
}