# 1. On définit le fournisseur (AWS) et la région
provider "aws" {
  region = "eu-west-3" # Paris
}

# 2. On crée un VPC (ton réseau privé virtuel)
resource "aws_vpc" "mon_reseau_secu" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "VPC-PROJET-SECU"
  }
}

# 3. On crée un sous-réseau (Subnet) à l'intérieur du VPC
resource "aws_subnet" "subnet_public" {
  vpc_id     = aws_vpc.mon_reseau_secu.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "Subnet-Public"
  }
}






# 4. Création du Pare-feu (Security Group)
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Autoriser le trafic HTTP"
  vpc_id      = aws_vpc.mon_reseau_secu.id

  # Règle entrante : On autorise le port 80 (HTTP) pour tout le monde
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Règle sortante : On autorise le serveur à sortir sur internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5. Création du serveur (Instance EC2)
# Ce bloc cherche l'AMI Ubuntu la plus récente
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # ID officiel de Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# Ton instance modifiée pour utiliser le résultat de la recherche
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.ubuntu.id # <--- On utilise l'ID trouvé dynamiquement
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.subnet_public.id
  vpc_security_group_ids = [aws_security_group.allow_web.id]

  # On ajoute une IP publique pour pouvoir y accéder
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y nginx
              sudo systemctl start nginx
              EOF

  tags = {
    Name = "MonServeurSecu"
  }
}



# 6. La Porte (Internet Gateway)
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.mon_reseau_secu.id

  tags = {
    Name = "IGW-Projet"
  }
}

# 7. Le Panneau de signalisation (Route Table)
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.mon_reseau_secu.id

  route {
    cidr_block = "0.0.0.0/0" # Tout le trafic...
    gateway_id = aws_internet_gateway.gw.id # ...va vers la porte internet
  }

  tags = {
    Name = "RouteTable-Public"
  }
}

# 8. L'association (On lie la route au sous-réseau)
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rt.id
}
