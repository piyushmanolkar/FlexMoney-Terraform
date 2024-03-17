output "ami_instance_id" {
  description = "ID of the AMI Server"
  value = aws_instance.ec2_instance.id
}

output "load_balancer_url" {
  description = "ID of the AMI Server"
  value = aws_lb.load_balancer.dns_name
}