// Terraform generates the DB password, so we control the secret; the stored JSON has the same shape the app and Lambda already read.
resource "random_password" "db" {
  length  = 24
  special = false // RDS rejects some special characters in master passwords
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "p3-db-credentials"
  recovery_window_in_days = 0 // delete immediately on destroy, so the name can be reused on the next build
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db.result
  })
}