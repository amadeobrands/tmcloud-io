
variable "aws_access_key_id" {}
variable "aws_secret_key" {}
variable "aws_region" {
  default = "eu-central-1"
}

variable "ssh_key_name" {
  default = "swarm"
}

provider "aws" {
  access_key = "${var.aws_access_key_id}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.aws_region}"
}

variable "swarm_env" {
  default = "test"
}
variable "swarm_managers_count" {
  default = 1
}
variable "swarm_manager_instance_type" {
  default = "c4.large"
}
variable "swarm_workers_count" {
  default = 1
}
variable "swarm_worker_instance_type" {
  default = "m4.large"
}
variable "rds_postgres_count" {
  default = 1
}
variable "rds_postgres_password" {}
variable "rds_postgres_username" {
  default = "monkadmin"
}
variable "rds_postgres_version" {
  default = "10.3"
}
variable "rds_backup_retention_period" {
  default = 7
}
variable "rds_postgres_instance_class" {
  default = "db.t2.medium"
}
variable "rds_mysql_count" {
  default = 0
}
variable "rds_mysql_version" {
  default = "5.7"
}
variable "rds_mysql_instance_class" {
  default = "db.t2.medium"
}
variable "rds_mysql_password" {}
variable "rds_mysql_username" {
  default = "monkadmin"
}
