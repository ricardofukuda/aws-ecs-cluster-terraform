terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.64"
    }
  }
  
  backend "s3" {
    bucket = "terraform-ecs-fukuda" // TODO
    region = "sa-east-1"
    key    = "terraform.tfstate"
  }
}

provider "aws" {
  region = "sa-east-1"
}

##### NETWORKING #####
resource "aws_vpc" "vpc" {
  cidr_block = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc-${var.env}"
    Environment = var.env
  }
}

resource "aws_subnet" "subnet-private"{
  vpc_id = aws_vpc.vpc.id
  for_each = var.private_subnets
  cidr_block = each.value
  availability_zone = each.key
  map_public_ip_on_launch = false
  tags = {
    Name = "subnet-${each.key}-private-${var.env}"
    Environment = var.env
  }
}

resource "aws_subnet" "subnet-public"{
  vpc_id = aws_vpc.vpc.id
  for_each = var.public_subnets
  cidr_block = each.value
  availability_zone = each.key
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet-${each.key}-public-${var.env}"
    Environment = var.env
  }
}

resource "aws_default_route_table" "vpc-route-table" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id

  route = []

  tags = {
    Name = "rt-${var.env}"
    Environment = var.env
  }
}

resource "aws_route_table" "subnet-route-table-private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "rt-private-${var.env}"
    Environment = var.env
  }
}

resource "aws_route_table" "subnet-route-table-public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "rt-public-${var.env}"
    Environment = var.env
  }
}

resource "aws_route_table_association" "route_table_association_private" {
  subnet_id = aws_subnet.subnet-private[each.key].id
  route_table_id = aws_route_table.subnet-route-table-private.id
  for_each = var.private_subnets
}

resource "aws_route_table_association" "route_table_association_public" {
  subnet_id = aws_subnet.subnet-public[each.key].id
  route_table_id = aws_route_table.subnet-route-table-public.id
  for_each = var.public_subnets
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "igw-${var.env}",
    Environment = var.env
  }
}

resource "aws_nat_gateway" "ngw" {
  subnet_id = aws_subnet.subnet-public[element(keys(var.public_subnets),0)].id
  connectivity_type = "public"
  allocation_id = aws_eip.eip_ngw.id
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "ngw-${var.env}"
    Environment = var.env
  }
}

resource "aws_eip" "eip_ngw" {
  vpc = true
  tags = {
    Name = "eip-ngw-${var.env}"
    Environment = terraform.workspace
  }
}

resource "aws_route" "igw-route-private" {
  route_table_id = aws_route_table.subnet-route-table-private.id
  destination_cidr_block = "0.0.0.0/0"
  #gateway_id  = aws_internet_gateway.igw.id
  gateway_id = aws_nat_gateway.ngw.id
}

resource "aws_route" "igw-route-public" {
  route_table_id = aws_route_table.subnet-route-table-public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
}



#### ECS Cluster #####
resource "aws_ecs_cluster" "ecs-cluster" {
  name = "ecs-cluster-${var.env}"

  capacity_providers = [aws_ecs_capacity_provider.ecs-capacity-provider.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs-capacity-provider.name
    weight = 1
    base = 0
  }

  tags = {
    Name = "ecs-cluster-${var.env}",
    Environment = var.env
  }

  depends_on = [
    aws_ecs_capacity_provider.ecs-capacity-provider
  ]
}

resource "aws_iam_instance_profile" "ec2-instance-profile" {
  name = "ec2-instance-profile-${var.env}"
  role = "ecsInstanceRole" // must exist in account

  lifecycle{
    create_before_destroy = false
  }
}

resource "aws_launch_template" "lt-ecs-instance" {
  name_prefix = "lt-ecs-instance-${var.env}"
  image_id = "ami-035b4cb75ab88f259"
  instance_type = "t3.nano"

  vpc_security_group_ids = [aws_security_group.sg-ecs-instance.id]
  user_data  = base64encode("#!/bin/bash\necho ECS_CLUSTER='ecs-cluster-homolog' > /etc/ecs/ecs.config")

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2-instance-profile.id
  }
  #key_name = "ecs-ec2-instance-${var.env}"

  credit_specification {
    cpu_credits = "standard"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "ecs-instance-${var.env}"
    }
  }
}

resource "aws_security_group" "sg-ecs-instance" {
  name        = "ecs-instance-${var.env}"
  description = "ecs-instance-${var.env}"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "accept all traffic from ELB"
    from_port        = 0
    to_port          = 65535
    protocol         = "tcp"
    ipv6_cidr_blocks = []
    cidr_blocks      = []
    security_groups = [aws_security_group.alb-sg.id]
  }

#  ingress {
#    description      = "SSH from VPC"
#    from_port        = 22
#    to_port          = 22
#    protocol         = "tcp"
#    cidr_blocks      = ["0.0.0.0/0"]
#    ipv6_cidr_blocks = []
#  }

  egress {
    description      = "Out"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ecs-instance-${var.env}"
    Environment = var.env
  }
}

resource "aws_placement_group" "ecs-instances-placement-group" {
  name     = "ecs-instances-placement-group-${var.env}"
  strategy = "partition"
  partition_count = 1
}

resource "aws_autoscaling_group" "asg" {
  name = "ecs-asg-${var.env}"
 
  desired_capacity = 1
  max_size = 1
  min_size = 1

  placement_group = aws_placement_group.ecs-instances-placement-group.id
  target_group_arns = [aws_lb_target_group.alb-ecs-tg-apache.arn]
  vpc_zone_identifier = [for vm in keys(var.private_subnets) : aws_subnet.subnet-private[vm].id] // may requires nat

  launch_template {
    id = aws_launch_template.lt-ecs-instance.id
    version = "$Latest"
  }

  lifecycle{
    create_before_destroy = false
  }

  tag {
    key = "AmazonECSManaged"
    value = "enabled"
    propagate_at_launch = true
  }

  depends_on = [
    aws_vpc.vpc
  ]
}

resource "aws_ecs_capacity_provider" "ecs-capacity-provider" {
  name = "capacity-provider-ecs-${var.env}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.asg.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}


### ALB ###
resource "aws_security_group" "alb-sg" {
  name        = "alb-${var.env}"
  description = "alb-${var.env}"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "public HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    ipv6_cidr_blocks = []
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    description      = "Out"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "alb-${var.env}"
    Environment = var.env
  }
}


resource "aws_lb" "alb" {
  name = "alb-${var.env}"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb-sg.id]
  subnets = [for vm in keys(var.public_subnets) : aws_subnet.subnet-public[vm].id]

  enable_deletion_protection = false 

  tags = {
    Name = "alb-${var.env}"
    Environment = var.env
  }
}

resource "aws_lb_listener" "alb-listener-default" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-ecs-tg-apache.arn
  }
}

resource "aws_lb_target_group" "alb-ecs-tg-apache" {
  name     = "alb-ecs-tg-apache-${var.env}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
}

resource "aws_ecs_task_definition" "ecs-task-definition-apache" {
  family = "apache"
  cpu = 128
  memory = 128
  execution_role_arn = "arn:aws:iam::127923327338:role/ecsTaskExecutionRole" // must exist
  container_definitions = jsonencode([
    {
      name      = "apache"
      image     = "httpd:2.4.51"
      cpu       = 128
      memory    = 128
      essential = true
      environment = []
      
      portMappings = [
        {
          containerPort = 80
          hostPort      = 0
          protocal = "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "ecs-service-apache" {
  name            = "apache"
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.ecs-task-definition-apache.arn
  desired_count   = 1

  health_check_grace_period_seconds = 60
  
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs-capacity-provider.name
    weight = 1
    base = 0
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alb-ecs-tg-apache.arn
    container_name   = "apache"
    container_port   = 80
  }
  
}