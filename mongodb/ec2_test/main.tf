provider "aws" {
    region = var.region  # Change to your desired region
}

resource "aws_security_group" "ec2-interview-sg" {
  name        = var.security_group_name
  description = "Security group for the interview instances"

  // Ingress rule allowing all traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Egress rule allowing all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app-interview-instance" {
  count = var.app_create_instance ? 1 : 0
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.ec2-interview-sg.name]  # Specify the security group name
  root_block_device {
    volume_size = 100  # Size in GB
  }
  tags = {
    Name = "${var.candidate_name}-app"
  }
}

resource "aws_instance" "mongo-interview-instances" {
  count         = var.instance_count
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.ec2-interview-sg.name]  # Specify the security group name
  root_block_device {
    volume_size = 100  # Size in GB
  }  
  tags = {
    Name = "${var.candidate_name}-mongo-rs-${count.index}"
  }
}

output "mongo_instance_ips" {
  value = aws_instance.mongo-interview-instances.*.public_ip
}

output "app_instance_ip" {
  value = aws_instance.app-interview-instance.*.public_ip
}

// Create Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = <<EOF
[all]
${aws_instance.app-interview-instance.*.public_ip[0]}
%{ for ip in aws_instance.mongo-interview-instances.*.public_ip }
${ip}
%{ endfor }

[app]
${aws_instance.app-interview-instance.*.public_ip[0]}

[mongo_replica_set]
%{ for ip in aws_instance.mongo-interview-instances.*.public_ip }
${ip}
%{ endfor }
EOF
  filename = "${path.module}/inventory.ini"
}
