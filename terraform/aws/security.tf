// ALB security group - the only thing the internet can talk to.
// Port 80 only for now: no certificate means no HTTPS, fine for a time-boxed demo.
resource "aws_security_group" "alb" {
  name   = "alb-p3-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // anywhere on the internet
  }

  // Terraform removes AWS's default "allow all out" rule, so outbound must be declared.
  // protocol "-1" = all protocols, ports 0 = all ports.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-alb" }
}

// Web tier security group - accepts traffic ONLY from the ALB's group, never from an IP range.
resource "aws_security_group" "web" {
  name   = "web-p3-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] // group reference: only ALB members may connect
  }

  // Outbound: call the app tier, pull images (via NAT), reach AWS APIs.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-web" }
}

// App tier security group - accepts traffic ONLY from the web tier (the tier-to-tier rule from Azure).
resource "aws_security_group" "app" {
  name   = "app-p3-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id] // the internet and the ALB can't reach the app tier directly
  }

  // Outbound: read the DB secret, talk to RDS, pull images.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-app" }
}

// RDS security group - Postgres (5432) only from the app tier. No egress rule needed:
// security groups are stateful, so replies to an allowed connection go out automatically.
resource "aws_security_group" "rds" {
  name   = "rds-p3-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id] // only app tasks can reach the database
  }

    ingress {
    description     = "Postgres from Lambda"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  tags = { Name = "sg-rds" }
}