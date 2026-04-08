# 1. Configuration du Provider
provider "aws" {
  region = "eu-west-3" # Paris
}

# 2. Recherche de l'AMI Ubuntu la plus récente (Pratique DevOps)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# 3. Réseau (VPC)
resource "aws_vpc" "mon_reseau_secu" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "VPC-PROJET-SECU"
  }
}

# 4. Sous-réseau (Subnet)
resource "aws_subnet" "subnet_public" {
  vpc_id                  = aws_vpc.mon_reseau_secu.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # Nécessaire pour accéder au web

  tags = {
    Name = "Subnet-Public"
  }
}

# 5. Porte de sortie (Internet Gateway)
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.mon_reseau_secu.id

  tags = {
    Name = "IGW-Projet"
  }
}

# 6. Table de routage
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.mon_reseau_secu.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "RouteTable-Public"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rt.id
}

# 7. Pare-feu (Security Group) avec descriptions (Fix Checkov)
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Autorise le flux HTTP entrant pour le serveur Web"
  vpc_id      = aws_vpc.mon_reseau_secu.id

  ingress {
    description = "Acces HTTP depuis Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Checkov va toujours signaler ceci, c'est normal pour un serveur public
  }

  egress {
    description = "Autorise toute sortie"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG-Web-Server"
  }
}

# 8. Le Serveur (Instance EC2) DURCI
resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.subnet_public.id
  vpc_security_group_ids      = [aws_security_group.allow_web.id]
  associate_public_ip_address = true

  # FIX CKV_AWS_8 : Chiffrement du disque dur
  root_block_device {
    encrypted = true
  }

  # FIX CKV_AWS_79 : Sécurisation du service de Metadata (IMDSv2)
  metadata_options {
    http_tokens = "required"
    http_endpoint = "enabled"
  }

  # FIX CKV_AWS_126 : Activation du monitoring détaillé
  monitoring = true

  # FIX CKV_AWS_135 : Optimisation EBS (si supporté par l'instance)
  ebs_optimized = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y nginx
              sudo systemctl start nginx
              EOF

  tags = {
    Name = "Serveur-Web-Securise"
  }
}

# 9. Output pour récupérer l'IP facilement
output "public_ip" {
  description = "Adresse IP publique du serveur"
  value       = aws_instance.web_server.public_ip
}
