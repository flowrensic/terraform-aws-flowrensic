resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.database_subnet_ids
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "flowrensic"
  username                    = "flowrensic"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period  = 7
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true
  apply_immediately        = true
}

resource "aws_secretsmanager_secret_rotation" "database" {
  secret_id = aws_db_instance.this.master_user_secret[0].secret_arn
  rotation_rules {
    automatically_after_days = 365
  }
}
