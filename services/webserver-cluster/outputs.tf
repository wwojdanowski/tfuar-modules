output "webapp_public_ip" {
  value = aws_lb.load_balancer.dns_name
  description = "The domain name of the load balancer"
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
  description = "The ID of the Security Group attached to the load balancer"
}