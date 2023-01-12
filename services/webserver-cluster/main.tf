resource "aws_security_group" "secgroup1" {
  name = "terraform-security-group-1"
  ingress {
    from_port = var.server_port
    protocol = "tcp"
    to_port = var.server_port
    cidr_blocks = [
      "0.0.0.0/0"]
  }
}

resource "aws_launch_configuration" "lc1" {
  image_id = "ami-0a6b2839d44d781b2"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.secgroup1.id]

  user_data = templatefile("${path.module}/user-data.sh", {
    server_port = var.server_port,
    db_address = data.terraform_remote_state.db.outputs.addres
    db_port = data.terraform_remote_state.db.outputs.port
  })

  lifecycle {
    create_before_destroy = true
  }

}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [
      data.aws_vpc.default.id]
  }
}

resource "aws_autoscaling_group" "asg1" {
  max_size = 2
  min_size = 1
  launch_configuration = aws_launch_configuration.lc1.name
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [
    aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  tag {
    key = "Name"
    propagate_at_launch = true
    value = "terraform-asg-example"
  }
}


resource "aws_lb" "load_balancer" {
  name = "terraform-asg-lb"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [
    aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = "404"
    }
  }
}

locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = [
    "0.0.0.0/0"]
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port = local.http_port
  protocol = local.tcp_protocol
  to_port = local.http_port
  cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id
  from_port = local.any_port
  protocol = local.any_protocol
  to_port = local.any_port
  cidr_blocks = local.all_ips
}

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100
  condition {
    path_pattern {
      values = [
        "*"]
    }
  }
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}


data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state_key
    region = "us-east-1"
  }
}