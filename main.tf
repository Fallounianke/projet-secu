Voici le fichier main.tf complet et optimisé. J'y ai ajouté des commentaires spécifiques pour "calmer" le scanner Checkov sur les points que nous acceptons (comme l'IP publique), tout en corrigeant les failles de sécurité réelles.

Efface tout dans ton fichier main.tf et colle ceci :
Terraform

# 1. LE CERVEAU COMMUN (BACKEND S3)
terraform {
  backend "s3" {
    bucket         = "tfstate-fallou-12345" # Vérifie bien ce nom !
    key            = "terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
  }
}

# 2. CONFIGURATION AWS
provider "aws" {
  region = "eu-west-3"
}

# 3. RECHERCHE DE L'IMAGE UBUNTU
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# 4. RÉSEAU (VPC)
# checkov:skip=CKV2_AWS_11: "Flow logs non activés pour économiser les coûts de lab"
resource "aws_vpc" "mon_reseau_secu" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "VPC-PROJET-SECU" }
}

# checkov:skip=CKV_AWS_130: "IP publique par défaut assumée pour ce serveur web"
resource "aws_subnet" "subnet_public" {
  vpc_id                  = aws_vpc.mon_reseau_secu.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.mon_reseau_secu.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.mon_reseau_secu.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rt.id
}

# 5. SÉCURITÉ (SECURITY GROUP)
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Autorise le flux HTTP entrant"
  vpc_id      = aws_vpc.mon_reseau_secu.id

  # checkov:skip=CKV_AWS_260: "Port 80 ouvert car c'est un serveur Web public"
  ingress {
    description = "Acces HTTP depuis Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # checkov:skip=CKV_AWS_382: "Sortie illimitée acceptée pour les mises à jour"
  egress {
    description = "Autorise toute sortie"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. LE SERVEUR UNIQUE ET DURCI
# checkov:skip=CKV_AWS_88: "IP publique nécessaire pour l'accès utilisateur"
# checkov:skip=CKV2_AWS_41: "Rôle IAM non nécessaire pour ce serveur de test"
resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.subnet_public.id
  vpc_security_group_ids      = [aws_security_group.allow_web.id]
  associate_public_ip_address = true

  # Correction Sécu : Chiffrement du disque
  root_block_device {
    encrypted = true
  }

  # Correction Sécu : Protection contre le vol de credentials
  metadata_options {
    http_tokens = "required"
    http_endpoint = "enabled"
  }

  monitoring = true
  ebs_optimized = true

  user_data = <<-EOF
              #!/bash/bash
              sudo apt update -y
              sudo apt install -y nginx
              sudo systemctl start nginx
              EOF

  tags = { Name = "Serveur-Web-Securise" }
}

output "public_ip" {
  description = "L'IP de ton site web"
  value = aws_instance.web_server.public_ip
}
