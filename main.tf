provider "aws" {
  region = "ap-south-1"
}

# VPC
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.env}-${var.vpc_name}"
  }
}

# Security Group For EC2 Instances
resource "aws_security_group" "ec2_sg" {
  name = "${var.env}-ec2-sg"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group For EC2 Instances
resource "aws_security_group" "ami_sg" {
  name = "${var.env}-ami-sg"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group For ALB
resource "aws_security_group" "alb_sg" {
  name = "${var.env}-alb-sg"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create Role For SSM EC2 Instances
resource "aws_iam_role" "iam_role" {
  name        = "${var.env}-ec2-ssm-iam-role"
  description = "The role for the developer resources EC2"
  assume_role_policy = jsonencode(
  {
    "Version": "2012-10-17",
    "Statement": {
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  })
}

# Create Profile For EC2 Instances
resource "aws_iam_instance_profile" "iam_instance_profile" {
  name = "${var.env}-ssm-iam-profile"
  role = aws_iam_role.iam_role.name
}

# Attach Role
resource "aws_iam_role_policy_attachment" "dev_resources_ssm_policy" {
  role       = aws_iam_role.iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Define EC2 instance resource
resource "aws_instance" "ec2_instance" {
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_1a.id
  vpc_security_group_ids = [ aws_security_group.ami_sg.id ]
  iam_instance_profile = aws_iam_instance_profile.iam_instance_profile.name
  user_data = templatefile("./user-data.tftpl", {backend_branch = var.backend_branch, frontend_branch = var.frontend_branch})
  key_name = "AutoScalingKey"
  
  associate_public_ip_address = true

  tags = {
    Name = "${var.env}-ami-ec2-instance"
  }
  
}

resource "time_sleep" "wait_120_seconds" {
  depends_on = [aws_instance.ec2_instance]

  create_duration = "120s"
}

# Create AMI from the EC2 instance
resource "aws_ami_from_instance" "dep_ami" {
  name                = "${var.env}-ami"
  source_instance_id         = aws_instance.ec2_instance.id
  depends_on          = [time_sleep.wait_120_seconds]
}

# resource "aws_ec2_instance_state" "ec2_instance" {
#   depends_on = [aws_ami_from_instance.dep_ami]
#   instance_id = aws_instance.ec2_instance.id
#   state       = "stopped"
# }

# EC2 Lauch Template
resource "aws_launch_template" "launch_template" {
  name_prefix   = "${var.env}-asg-lt-"
  image_id      = aws_ami_from_instance.dep_ami.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.iam_instance_profile.name
  }

  vpc_security_group_ids = [ aws_security_group.ec2_sg.id ]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.env}-${var.instance_name}"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Public Subnets
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "${var.env}-public-1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "${var.env}-public-1b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.env}-internet-gateway"
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "${var.env}-public-rt"
  }
}

# Association of Subnet to Route Table
resource "aws_route_table_association" "public_rt_subnet_assoc_1a" {
  subnet_id = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}

# Association of Subnet to Route Table
resource "aws_route_table_association" "public_rt_subnet_assoc_1b" {
  subnet_id = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Subnets
resource "aws_subnet" "private_1a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "${var.env}-private-1a"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "${var.env}-private-1b"
  }
}

# Elastic IP For NAT Gateway
resource "aws_eip" "nat_gateway_eip" {}

# NAT Gateway
resource "aws_nat_gateway" "dev_nat_gw" {
  subnet_id = aws_subnet.public_1a.id
  allocation_id = aws_eip.nat_gateway_eip.id

  tags = {
    Name = "${var.env}-nat-gateway"
  }
}

# Route Table For Private Subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dev_nat_gw.id
  }

  tags = {
    Name = "${var.env}-private-rt"
  }
}

# Association of Subnet to Route Table
resource "aws_route_table_association" "private_rt_subnet_assoc_1a" {
  subnet_id = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_rt.id
}

# Association of Subnet to Route Table
resource "aws_route_table_association" "private_rt_subnet_assoc_1b" {
  subnet_id = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private_rt.id
}

# Auto-Scaling Group
resource "aws_autoscaling_group" "auto_scaling_group" {
  name                 = "${var.env}-asg"
  min_size             = var.auto_scaling_min
  max_size             = var.auto_scaling_max
  desired_capacity     = var.auto_scaling_desired
  
  vpc_zone_identifier  = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  health_check_type    = "ELB"

  launch_template {
    id      = aws_launch_template.launch_template.id
    version = "$Latest"
  }
}

# Load Balancer
resource "aws_lb" "load_balancer" {
  name               = "${var.env}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

# Listener for ALB
resource "aws_lb_listener" "load_balancer_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.load_balancer_tg.arn
  }
}

# Target Group For ALB
resource "aws_lb_target_group" "load_balancer_tg" {
  name     = "${var.env}-load-balancer-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    path = "/"
    interval = "60"
    timeout = "20"
  }
}

# Association for autoscaling group
resource "aws_autoscaling_attachment" "dev_autoscaling_attachment" {
  autoscaling_group_name = aws_autoscaling_group.auto_scaling_group.id
  lb_target_group_arn = aws_lb_target_group.load_balancer_tg.arn
}

# Create a CloudWatch Metric Alarm for CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "${var.env}-cpu-utilization-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"  # Number of consecutive periods the metric must be breaching to trigger the alarm
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"  # Length of each period in seconds (5 minutes)
  statistic           = "Average"
  threshold           = "75"  # Threshold for triggering the alarm, in percentage
  alarm_description   = "Alarm when CPU exceeds 75%"
  alarm_actions       = [aws_autoscaling_policy.scale_out_policy.arn]  # Action to trigger when alarm is in ALARM state
}

# Scaling Policy for scaling out
resource "aws_autoscaling_policy" "scale_out_policy" {
  name                   = "${var.env}-scale-out-policy"
  scaling_adjustment     = 1  # Increase by one instance
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300  # Cooldown period in seconds to prevent rapid scaling
  autoscaling_group_name = aws_autoscaling_group.auto_scaling_group.name
}