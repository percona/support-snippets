variable "region" {
  description = "AWS region where instances will be deployed"
  type        = string
}

variable "ami_id" {
  description = "AMI ID of the instance image"
  type        = string
}

variable "key_name" {
  description = "Name of the AWS key pair"
  type        = string
}

variable "security_group_name" {
  description = "Name of the AWS security group"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "instance_count" {
  description = "Number of EC2 instances to be deployed"
  type        = number
}

variable "candidate_name" {
  description = "The candidate applying for the EC2 exam"
  type        = string
}

variable "app_create_instance" {
  description = "If true, Application server will be deployed"
  type        = bool
}
