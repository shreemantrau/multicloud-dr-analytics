// DB subnet group - tells RDS which subnets it may use. Needs subnets in 2+ zones, even for a single-zone database.
// Both are PRIVATE, so the database has no route to or from the internet.
resource "aws_db_subnet_group" "main" {
  name       = "p3-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "db-subnet-group" }
}

// RDS PostgreSQL instance - the data tier (Azure SQL equivalent).
resource "aws_db_instance" "main" {
  identifier = "p3-postgres"

  engine         = "postgres"
  engine_version = "16"           // latest 16.x minor version AWS offers
  instance_class = "db.t4g.micro" // cheapest class (~$0.016/hr). 

  // gp3 SSD, 20 GB is the minimum allowed. Storage is billed per GB-month whether used or not.
  storage_type          = "gp3"
  allocated_storage     = 20
  max_allocated_storage = 0 // 0 = no autoscaling, so storage can't grow (and bill) behind our back

  db_name  = "appdb"   // initial database created inside the server
  username = "dbadmin" // master user name

  // The password comes from the random_password resource and is stored in Secrets Manager (secrets.tf).
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id] // the SG link: only the app tier can reach 5432
  publicly_accessible    = false                       // no public IP, private only (Project 2 had this true for the sync)

  multi_az                = false // single zone, half the cost. Fine for a demo
  backup_retention_period = 0     // no automated backups (cost). Production would use 7+
  skip_final_snapshot     = true  // destroy without creating a final snapshot
  deletion_protection     = false // lets terraform destroy work
  apply_immediately       = true  // don't wait for the maintenance window

  tags = { Name = "rds-p3-postgres" }
}