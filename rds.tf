# Full mode only. Standalone runs Postgres inside the server task.
resource "aws_db_subnet_group" "this" {
  count      = local.full
  name       = var.name
  subnet_ids = var.database_subnet_ids
}

resource "aws_db_instance" "this" {
  count          = local.full
  identifier     = var.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = local.database_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "flowrensic"
  username                    = "flowrensic"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this[0].name
  vpc_security_group_ids = [aws_security_group.database[0].id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period  = 7
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true
  apply_immediately        = true
}

resource "aws_secretsmanager_secret_rotation" "database" {
  count     = local.full
  secret_id = aws_db_instance.this[0].master_user_secret[0].secret_arn
  rotation_rules {
    automatically_after_days = 365
  }
}

# Moves a state of the releases before, which had no count, to index 0.
moved {
  from = aws_db_subnet_group.this
  to   = aws_db_subnet_group.this[0]
}

moved {
  from = aws_db_instance.this
  to   = aws_db_instance.this[0]
}

moved {
  from = aws_secretsmanager_secret_rotation.database
  to   = aws_secretsmanager_secret_rotation.database[0]
}

moved {
  from = aws_security_group.database
  to   = aws_security_group.database[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.database
  to   = aws_vpc_security_group_ingress_rule.database[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.database_memory
  to   = aws_cloudwatch_metric_alarm.database_memory[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.database_swap
  to   = aws_cloudwatch_metric_alarm.database_swap[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.database_storage
  to   = aws_cloudwatch_metric_alarm.database_storage[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.database_cpu
  to   = aws_cloudwatch_metric_alarm.database_cpu[0]
}
