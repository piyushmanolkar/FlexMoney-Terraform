variable "branch" {
  description = "Branch name for resource tagging"
  type        = string
  default = "dev"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default = "vpc"
}

variable "instance_name" {
  description = "Name of the EC2 instance"
  type        = string
  default = "spring-boot-server"
}

variable "ami" {
  description = "AMI ID for EC2 instances"
  type        = string
  default = "ami-026255a2746f88074"
}

variable "instance_type" {
  description = "Instance type for EC2 instances"
  type        = string
  default = "t3.micro"
}

variable "auto_scaling_min" {
  description = "Minimum number of instances in the auto-scaling group"
  type        = number
  default = 1
}

variable "auto_scaling_max" {
  description = "Maximum number of instances in the auto-scaling group"
  type        = number
  default = 5
}

variable "auto_scaling_desired" {
  description = "Desired number of instances in the auto-scaling group"
  type        = number
  default = 2
}
