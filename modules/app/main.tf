#VPC, private and public subnets, nat gateway for private subnets.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.21.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  enable_dns_hostnames = true

  azs             = var.vpc_azs
  private_subnets = var.vpc_private_subnets
  public_subnets  = var.vpc_public_subnets

  enable_nat_gateway = var.vpc_enable_nat_gateway

  igw_tags = {
    Name = "${var.name}-igw"
  }
  nat_gateway_tags = {
    Name = "${var.name}-nat"
  }
}

#Security group for load balancer
module "load_balancer_sg" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "4.9.0"
  name        = "${var.name}-lb-sg"
  description = "Security group for application load balancer"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [
    "77.122.62.220/32",
    "89.162.139.30/32",
    "93.77.124.22/32",
    "89.162.139.0/24",
    "89.162.139.29/32",
    "46.211.100.254/32",
    "89.162.139.28/32",
    "178.74.230.158/32"
  ]

  ingress_rules = [
    "http-80-tcp",
    "https-443-tcp"
  ]
  egress_cidr_blocks = [
    "0.0.0.0/0"
  ]
  egress_rules = [
    "all-all"
  ]
  depends_on = [
    module.vpc
  ]
}

#Security group for RDS
module "db_sg" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "4.9.0"
  name        = "${var.name}-db-sg"
  description = "Security group for database"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [
    "10.0.3.0/24",
    "10.0.4.0/24"
  ]

  ingress_rules = [
    "mysql-tcp"
  ]
  egress_cidr_blocks = [
    "0.0.0.0/0"
  ]
  egress_rules = [
    "all-all"
  ]
  depends_on = [
    module.vpc
  ]
}

#Security group for bastion host
module "bastion_sg" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "4.9.0"
  name        = "${var.name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]

  ingress_rules = [
    "ssh-tcp"
  ]
  egress_cidr_blocks = [
    "0.0.0.0/0"
  ]
  egress_rules = [
    "all-all"
  ]
  depends_on = [
    module.vpc
  ]
}

#Security group for ASG
module "asg_sg" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "4.9.0"
  name        = "${var.name}-asg-sg"
  description = "Security group for Auto-scaling group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "ssh-tcp"
      source_security_group_id = module.bastion_sg.security_group_id
    },
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.load_balancer_sg.security_group_id
    },
    {
      rule                     = "https-443-tcp"
      source_security_group_id = module.load_balancer_sg.security_group_id
    }
  ]
  egress_cidr_blocks = [
    "0.0.0.0/0"
  ]
  egress_rules = [
    "all-all"
  ]
  depends_on = [
    module.vpc
  ]
}

#Private .pem key for instances
resource "tls_private_key" "private_pem_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "pem-key"
  public_key = tls_private_key.private_pem_key.public_key_openssh
}

#S3 endpoint
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_endpoint_type = "Gateway"
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-1.s3"

  route_table_ids = ["${module.vpc.public_route_table_ids[0]}"]

  tags = {
    Name = "${var.name}-endpoint"
  }
}

#Subnet group for RDS
resource "aws_db_subnet_group" "terraform_db_group" {
  name       = "terraform_db_group"
  subnet_ids = [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

#RDS instance
resource "aws_db_instance" "terraform_db" {
  allocated_storage = 20
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t2.micro"
  username            = "root"
  password            = "pas12345"
  skip_final_snapshot = true

  db_subnet_group_name = aws_db_subnet_group.terraform_db_group.id

  vpc_security_group_ids = [module.db_sg.security_group_id]
}

#Adding A record for Route53
resource "aws_route53_record" "a_record" {
  zone_id = "Z04511612EYQ57NS0T4FI"
  name    = "iangodbx.pp.ua"
  type    = "A"
  #change name 
  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

#S3 bucket with PHP application
resource "aws_s3_bucket" "php_crud" {
  bucket = "${var.name}-s3-bucket-23681531"
  tags = {
    Name = "${var.name}-s3-bucket-23681531"
  }
}

#Make S3 bucket private
resource "aws_s3_bucket_acl" "example" {
  bucket = aws_s3_bucket.php_crud.id
  acl    = "private"
}

#Upload PHP application files to S3 bucket
resource "aws_s3_object" "php_crud" {
  for_each = fileset(var.upload_directory, "**/*.*")
  bucket   = aws_s3_bucket.php_crud.id
  key      = each.value
  source   = "${var.upload_directory}${each.value}"
  etag     = filemd5("${var.upload_directory}${each.value}")

  depends_on = [
    aws_s3_bucket.php_crud
  ]
}

#Choose AMI for instances 
data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["137112412989"]
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

#Bastion host
resource "aws_instance" "bastion" {
  ami             = data.aws_ami.amazon-linux-2.id
  instance_type   = var.instance_type
  security_groups = [module.bastion_sg.security_group_id]
  subnet_id       = module.vpc.public_subnets[0]
  user_data = templatefile("scripts/bastion.sh.tftpl", { ssh_public = var.public_key })
  key_name  = aws_key_pair.generated_key.key_name

  tags = {
    Name = "${var.name}-bastion"
  }
}

#Launch configuration for ASG
resource "aws_launch_configuration" "as_conf" {
  name_prefix                 = "${var.name}-lc-"
  image_id                    = data.aws_ami.amazon-linux-2.id
  instance_type               = var.instance_type
  user_data                   = file("./scripts/phpcr.sh")
  associate_public_ip_address = false
  security_groups             = [module.asg_sg.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.terraform_asg.id
  key_name                    = aws_key_pair.generated_key.key_name

  lifecycle {
    create_before_destroy = true
  }
  root_block_device {
    volume_size           = var.add_volume_size
    volume_type           = "gp2"
    delete_on_termination = true
  }

  depends_on = [
    aws_db_instance.terraform_db
  ]
}

#Additional volume 
resource "aws_volume_attachment" "ebs_att_bastion" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.add_volume_bastion.id
  instance_id = aws_instance.bastion.id
}

resource "aws_ebs_volume" "add_volume_bastion" {
  availability_zone = "us-east-1a"
  size              = var.add_volume_size
}

#IAM roles for ASG
resource "aws_iam_instance_profile" "terraform_asg" {
  name = "S3RDS"
  role = aws_iam_role.asg_php_access.name
}

resource "aws_iam_role" "asg_php_access" {
  name = "asg_php_access"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "role-policy-attachment" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ])

  role       = aws_iam_role.asg_php_access.name
  policy_arn = each.value
}

#ASG
resource "aws_autoscaling_group" "lb_asg" {
  name                 = "${var.name}-asg"
  launch_configuration = aws_launch_configuration.as_conf.name
  vpc_zone_identifier  = [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]
  min_size             = 2
  max_size             = 2
  target_group_arns    = [aws_lb_target_group.https_tg.arn]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-asg-webserver"
    propagate_at_launch = true
  }
}

#Targer group for ASG
resource "aws_lb_target_group" "https_tg" {
  name     = "tf-example-lb-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = module.vpc.vpc_id
}

#Application load balancer
resource "aws_lb" "alb" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.load_balancer_sg.security_group_id]
  subnets            = module.vpc.public_subnets

  tags = {
    Name = "${var.name}-alb"
  }
}

#Redirect to HTTPS application load balancer listener
resource "aws_lb_listener" "redirect_https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

#Forward to the targer group application load balancer listener
resource "aws_lb_listener" "https_tg" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:120450333118:certificate/d3bd957a-40bb-417b-8f8b-e4ed3e92f389"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https_tg.arn
  }
}