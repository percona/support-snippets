terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project_name" {
  type = string
}

variable "engineer_name" {
  type = string
}

variable "key_name" {
  type = string
}

variable "master_password" {
  type = string
  sensitive = true
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-west-1"
}

resource "aws_vpc" "jumphost" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "${var.engineer_name}-${var.project_name}-jumphost"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.jumphost.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "${var.engineer_name}-${var.project_name}-public-subnet"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.jumphost.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "${var.engineer_name}-${var.project_name}-private-subnet_1b"
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id            = aws_vpc.jumphost.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-west-1c"

  tags = {
    Name = "${var.engineer_name}-${var.project_name}-private-subnet_1c"
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.jumphost.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "${var.engineer_name}-${var.project_name}-private-subnet_1a"
  }
}

resource "aws_internet_gateway" "internet" {
  vpc_id = aws_vpc.jumphost.id

  tags = {
    Name = "${var.engineer_name}-${var.project_name}-internet-gateway"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.jumphost.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.internet.id
  }

  tags = {
    Name = "${var.engineer_name}-${var.project_name}-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name   = "${var.engineer_name}-${var.project_name}-web-access"
  vpc_id = aws_vpc.jumphost.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_access" {
  name   = "${var.engineer_name}-${var.project_name}-db-access"
  vpc_id = aws_vpc.jumphost.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_group" "web" {
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.web.name
  vpc_zone_identifier  = [aws_subnet.public.id] 

  tag {
      key                 = "Name"
      value               = "${var.engineer_name}-${var.project_name}-web-dummy-autoscaling"
      propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "web" {
  image_id      = "ami-062a49a8152e4c031"
  name_prefix   = "${var.engineer_name}-${var.project_name}-web"
  instance_type = "t2.nano"
  key_name      = "${var.key_name}"

  security_groups      = [aws_security_group.web.id]
  associate_public_ip_address = true

  user_data = <<-EOF
  #!/bin/bash -ex

  dnf install -y nginx
  echo '<h1>Hello, World!</h1>' >  /usr/share/nginx/html/index.html 
  systemctl enable nginx
  systemctl start nginx
  EOF

}

resource "aws_db_subnet_group" "db" {
  name       = "${var.engineer_name}-${var.project_name}-db"
  subnet_ids = [aws_subnet.private_1a.id,aws_subnet.private_1b.id,aws_subnet.private_1c.id]

  tags = {
    Name = "${var.engineer_name}-${var.project_name}-db-subnet"
  }
}


resource "aws_rds_cluster" "aurora_mysql" {
  cluster_identifier     = "${var.engineer_name}-${var.project_name}-aurora-cluster"
  availability_zones     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  vpc_security_group_ids = [aws_security_group.db_access.id]
  db_subnet_group_name   = aws_db_subnet_group.db.name 
  database_name          = "test"
  engine                 = "aurora-mysql"
  skip_final_snapshot    = true
  master_username        = "root"
  master_password        = var.master_password
}

resource "aws_rds_cluster_instance" "aurora_mysql" {
  count              = 1
  identifier         = "${var.engineer_name}-${var.project_name}-aurora-cluster-instance-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora_mysql.id
  engine             = "aurora-mysql"
  engine_version     = "8.0"
  instance_class     = "db.t3.medium"
}
