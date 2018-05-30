## Docker for AWS

resource "aws_cloudformation_stack" "swarm" {
  name = "${var.swarm_env}-docker-swarm"
  template_url = "https://editions-us-east-1.s3.amazonaws.com/aws/stable/Docker.tmpl"
  capabilities = ["CAPABILITY_IAM"]
  parameters {
    ClusterSize = "${var.swarm_workers_count}"
    EnableCloudStorEfs = "yes"
    EnableCloudWatchLogs = "yes"
    EnableEbsOptimized = "yes"
    EnableSystemPrune = "no"
    InstanceType = "${var.swarm_workers_instance_type}"
    KeyName = "${var.ssh_key_name}"
    ManagerDiskSize = 20
    ManagerDiskType = "gp2"
    ManagerInstanceType = "${var.swarm_managers_instance_type}"
    ManagerSize = "${var.swarm_managers_count}"
    WorkerDiskSize = 40
    WorkerDiskType = "gp2"
  }
}

output "swarm_vpc_id" {
  value = "${aws_cloudformation_stack.swarm.outputs["VPCID"]}"
}

output "swarm_node_security_group" {
  value = "${aws_cloudformation_stack.swarm.outputs["NodeSecurityGroupID"]}"
}

output "swarm_manager_secutity_group" {
  value = "${aws_cloudformation_stack.swarm.outputs["ManagerSecurityGroupID"]}"
}

output "swarm_loadbalancer_dns_target" {
  value = "${aws_cloudformation_stack.swarm.outputs["DefaultDNSTarget"]}"
}

output "swarm_loadbalancer_zone_id" {
  value = "${aws_cloudformation_stack.swarm.outputs["ELBDNSZoneID"]}"
}

output "swarm_managers" {
  value = "${aws_cloudformation_stack.swarm.outputs["Managers"]}"
}

## Swarm managers for stacks deployments

data "aws_instances" "managers" {
  instance_tags {
    Name = "${aws_cloudformation_stack.swarm.name}-Manager"
  }
}

output "swarm_managers_ids" {
  value = "${data.aws_instances.managers.ids[0]}"
}

## Swarmpit

data "template_file" "swarmpit-stack" {
  template = "${file("swarmpit/docker-compose.yml")}"

  vars {
    swarmpit_host = "swarmpit.${var.swarm_env}.tmcloud.io"
  }
}

resource "null_resource" "swarmpit" {
  depends_on = [
    "data.aws_instances.managers",
    "data.template_file.swarmpit-stack"
  ]
  connection {
    type = "ssh"
    user = "docker"
    private_key = "${file(var.ssh_key_file)}"

    host = "${element(data.aws_instances.managers.public_ips, 0)}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -rf ./swarmpit",
      "mkdir -p ./swarmpit"
    ]
  }

  provisioner "file" {
    content = "${data.template_file.swarmpit-stack.rendered}"
    destination = "./swarmpit/docker-compose.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "docker network create --driver overlay proxy",
      "docker stack deploy -c ./swarmpit/docker-compose.yml swarmpit"
    ]
  }
}

output "swarmpit-host" {
  value = "${data.template_file.swarmpit-stack.vars.swarmpit_host}"
}

## Traefik

data "template_file" "traefik-stack" {
  template = "${file("traefik/docker-compose.yml")}"

  vars {
    acme_ca_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
    acme_domains = "*.${var.swarm_env}.tmcloud.io,${var.swarm_env}.tmcloud.io"
    acme_aws_access_key = "${var.acme_aws_access_key}"
    acme_aws_secret_key = "${var.acme_aws_secret_key}"
    docker_domain = "${var.swarm_env}.tmcloud.io"
  }
}

resource "null_resource" "traefik" {
  depends_on = [
    "data.aws_instances.managers",
    "null_resource.swarmpit",
    "data.template_file.traefik-stack"
  ]
  connection {
    type = "ssh"
    user = "docker"
    private_key = "${file(var.ssh_key_file)}"

    host = "${element(data.aws_instances.managers.public_ips, 0)}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -rf ./traefik",
      "mkdir -p ./traefik"
    ]
  }

  provisioner "file" {
    content = "${data.template_file.traefik-stack.rendered}"
    destination = "./traefik/docker-compose.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "docker stack deploy -c ./traefik/docker-compose.yml traefik"
    ]
  }
}

## Swarm DBs subnet

data "aws_subnet_ids" "swarm" {
  depends_on = ["aws_cloudformation_stack.swarm"]
  vpc_id = "${aws_cloudformation_stack.swarm.outputs["VPCID"]}"
}

resource "aws_db_subnet_group" "swarm" {
  depends_on = ["data.aws_subnet_ids.swarm"]
  name_prefix = "${var.swarm_env}-swarm-"
  subnet_ids = ["${data.aws_subnet_ids.swarm.ids}"]
}

## Postgres DB

resource "aws_db_instance" "postgres" {
  depends_on = [
    "aws_cloudformation_stack.swarm",
    "aws_db_subnet_group.swarm"
  ]
  identifier = "${var.swarm_env}-postgres"
  name = "Postgres${title(var.swarm_env)}"
  count = "${var.rds_postgres_count}"
  engine = "postgres"
  engine_version = "${var.rds_postgres_version}"
  instance_class = "${var.rds_postgres_instance_class}"

  storage_type = "gp2"
  allocated_storage = 100
  auto_minor_version_upgrade = true
  backup_retention_period = "${var.rds_backup_retention_period}"
  skip_final_snapshot = true

  username = "${var.rds_postgres_username}"
  password = "${var.rds_postgres_password}"

  db_subnet_group_name = "${aws_db_subnet_group.swarm.name}"
  vpc_security_group_ids = [
    "${aws_cloudformation_stack.swarm.outputs["NodeSecurityGroupID"]}",
    "${aws_cloudformation_stack.swarm.outputs["ManagerSecurityGroupID"]}"
  ]
}

output "rds_postgres_address" {
  value = "${aws_db_instance.postgres.*.address}"
}

resource "null_resource" "postgres-password-secret" {
  depends_on = [
    "aws_db_instance.postgres",
    "data.aws_instances.managers"
  ]

  connection {
    type = "ssh"
    user = "docker"
    private_key = "${file(var.ssh_key_file)}"

    host = "${element(data.aws_instances.managers.public_ips, 0)}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '${var.rds_postgres_password}' | docker secret create postgress-password -"
    ]
  }
}

## MySQL DB

resource "aws_db_instance" "mysql" {
  depends_on = [
    "aws_cloudformation_stack.swarm",
    "aws_db_subnet_group.swarm"
  ]
  skip_final_snapshot = true
  identifier = "${var.swarm_env}-mysql"
  count = "${var.rds_mysql_count}"
  engine = "mysql"
  engine_version = "${var.rds_mysql_version}"
  instance_class = "${var.rds_mysql_instance_class}"

  storage_type = "gp2"
  allocated_storage = 20
  auto_minor_version_upgrade = true
  backup_retention_period = "${var.rds_backup_retention_period}"

  username = "${var.rds_mysql_username}"
  password = "${var.rds_mysql_password}"

  db_subnet_group_name = "${aws_db_subnet_group.swarm.name}"
  vpc_security_group_ids = [
    "${aws_cloudformation_stack.swarm.outputs["NodeSecurityGroupID"]}",
    "${aws_cloudformation_stack.swarm.outputs["ManagerSecurityGroupID"]}"
  ]
}

output "rds_mysql_address" {
  value = "${aws_db_instance.mysql.*.address}"
}

resource "null_resource" "mysql-password-secret" {
  depends_on = [
    "aws_db_instance.mysql",
    "data.aws_instances.managers"
  ]

  connection {
    type = "ssh"
    user = "docker"
    private_key = "${file(var.ssh_key_file)}"

    host = "${element(data.aws_instances.managers.public_ips, 0)}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '${var.rds_mysql_password}' | docker secret create mysql-password -"
    ]
  }
}

## DNS records

data "aws_route53_zone" "selected" {
  name = "tmcloud.io."
}

resource "aws_route53_record" "swarm-loadbalancer" {
  depends_on = ["aws_cloudformation_stack.swarm"]
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name = "${var.swarm_env}.${data.aws_route53_zone.selected.name}"
  type = "A"
  alias {
    name = "${aws_cloudformation_stack.swarm.outputs["DefaultDNSTarget"]}"
    zone_id = "${aws_cloudformation_stack.swarm.outputs["ELBDNSZoneID"]}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wildcard-record" {
  depends_on = ["aws_route53_record.swarm-loadbalancer"]
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name = "*.${var.swarm_env}.${data.aws_route53_zone.selected.name}"
  type = "CNAME"
  ttl = "300"
  records = ["${aws_route53_record.swarm-loadbalancer.name}"]
}

