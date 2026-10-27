// ---------- ALB: the only public entry point ----------
// Azure equivalent: Application Gateway. Sits in the PUBLIC subnets (needs 2 AZs).
resource "aws_lb" "main" {
  name               = "alb-p3-dr"
  load_balancer_type = "application"
  internal           = false // internet-facing
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups    = [aws_security_group.alb.id] // allows 80 from anywhere
}

// ---------- Target group: the pool the ALB forwards to ----------
resource "aws_lb_target_group" "web" {
  name        = "tg-p3-web"
  port        = 5000 //flask
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" // Fargate tasks register by IP (awsvpc), not by instance

  health_check {
    path    = "/health" // the web tier's /health route
    matcher = "200"
  }

  deregistration_delay = 30 // default is 300s; short so destroy and redeploys are fast
}

// ---------- Listener: "traffic arriving on port 80, send it to the web pool" ----------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

// ---------- Web service: keeps 1 web task running behind the ALB ----------
resource "aws_ecs_service" "web" {
  name            = "p3-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.web.id] // allows 5000 from the ALB SG only
    assign_public_ip = false
  }

  // Registers each web task's IP in the target group.
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web" // must match the container name in the task definition
    container_port   = 5000
  }

  // Terraform errors if the service is created before the listener ties the target group to the ALB.
  depends_on = [aws_lb_listener.http, aws_route.private_nat]
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}