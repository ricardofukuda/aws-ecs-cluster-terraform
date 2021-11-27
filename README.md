# Terraform for ECS Cluster using EC2 instances on AWS

## Contains:
- ECS Cluster using EC2 instances;
- Apache webserver running as ECS Service/Task;
- VPC with private and public subnets;
- Application Load Balancer (in public subnet);
- ECS/EC2 AutoScalingGroup with target scaling policy (Launch Template);
- InternetGateway for public subnet and NatGateway for private subnet isolation;