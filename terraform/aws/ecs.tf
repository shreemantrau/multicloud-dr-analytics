
// ---------- Logs ----------
// Containers write stdout here. Azure equivalent: Log Analytics.
// retention 1 day = cost control, it's a demo.
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/p3-web" //just naming conventions could be any other name ... with or without '/'
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/p3-app" //just naming conventions could be any other name ... with or without '/'
  retention_in_days = 1
}

// ---------- Cluster ----------
// Just a logical group that holds services. CECS must be created inside the Cluster 
// Fargate = AWS runs the servers, we only define containers.
resource "aws_ecs_cluster" "main" {
  name = "p3-dr"
}

// ---------- Task definition: app tier ----------
// The recipe for one container (like `docker run` written down).
resource "aws_ecs_task_definition" "app" {
  family                   = "p3-app"
  requires_compatibilities = ["FARGATE"] // Similar to App service in Azure ... it runs the container (serverless operation)
  network_mode             = "awsvpc"    // each task gets its own network interface, so security groups attach to the task
  cpu                      = 256         // smallest Fargate size (0.25 vCPU). This is the SKU.
  memory                   = 512         // MB, smallest allowed with 256 cpu

  execution_role_arn = aws_iam_role.task_execution.arn // ECS: pull image, write logs ... needed when getting started
  task_role_arn      = aws_iam_role.app_task.arn       // our code: read the DB secret ... runtime of code (python code)

  // Images were built on a Mac with --platform linux/amd64, so tell Fargate the same.
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "app"
    image        = "${aws_ecr_repository.app.repository_url}:v1"
    essential    = true
    portMappings = [{ containerPort = 5000 }]

    environment = [
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_NAME", value = "appdb" },
      { name = "DB_USER", value = "dbadmin" },
      // Python fetches the password itself with boto3 using this ARN, so it never appears in the task definition.
      { name = "DB_SECRET_ID", value = aws_secretsmanager_secret.db.arn },
      { name = "AWS_REGION", value = data.aws_region.current.name },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

// ---------- Task definition: web tier ----------
resource "aws_ecs_task_definition" "web" {
  family                   = "p3-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  execution_role_arn = aws_iam_role.task_execution.arn
  // No task_role_arn: the web code never calls AWS.

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "web"
    image        = "${aws_ecr_repository.web.repository_url}:v1"
    essential    = true
    portMappings = [{ containerPort = 5000 }]

    environment = [
      // Cloud Map private DNS name (created in the next step). Web finds app by name, not IP.
      { name = "APP_URL", value = "http://app.p3dr.local:5000" },
      { name = "CLOUD_NAME", value = "AWS" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.web.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "web"
      }
    }
  }])
}

// ---------- Cloud Map: private DNS inside the VPC ----------
// Task IPs change every restart. Web finds app by the name app.p3dr.local instead.
// Azure equivalent: Private DNS zone.
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "p3dr.local"
  vpc  = aws_vpc.main.id
}

// Registers the app under the name "app" -> app.p3dr.local
resource "aws_service_discovery_service" "app" {
  name = "app"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10 // short, so a restarted task's new IP is found fast
      type = "A"
    }
  }
}

// ---------- App service: keeps 1 copy of the app task running ----------
resource "aws_ecs_service" "app" {
  name            = "p3-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1 // cost control; 2 would be real HA
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.app.id] // allows 5000 from web only
    assign_public_ip = false                       // private, outbound via NAT
  }

  // Auto-registers the running task's IP under app.p3dr.local
  service_registries {
    registry_arn = aws_service_discovery_service.app.arn
  }

  // Task can't pull its image until the NAT route exists.
  depends_on = [aws_route.private_nat]
}