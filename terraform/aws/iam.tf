// Creates one shared identity ("badge") for ECS to use. The assume_role_policy
// is a trust rule saying ONLY the ECS service (ecs-tasks.amazonaws.com) can claim
// this identity — not a list of specific tasks, any ECS task can use this same one.
// No real permissions yet — this just defines WHO can wear the badge.

resource "aws_iam_role" "task_execution" {
  name = "p3-ecs-task-execution"

  // Trust policy: WHO may wear this role? The ECS tasks service.
  // Not a permission to do anything, only "who can assume it".
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

// WHAT can it do? Attach an AWS-managed policy: pull ECR images + write CloudWatch logs.
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// ---------- Task role: used by your Python code while it runs ----------
// Azure equivalent: Key Vault Secrets User. Only the app tier gets one.

resource "aws_iam_role" "app_task" {
  name = "p3-app-task"

  // Same trust policy: ECS tasks wear this role too.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

// Inline policy: the one thing the app may do.
// Least privilege: read ONE secret (the RDS password), nothing else.
resource "aws_iam_role_policy" "app_read_db_secret" {
  name = "read-db-secret"
  role = aws_iam_role.app_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db.arn
    }]
  })
}