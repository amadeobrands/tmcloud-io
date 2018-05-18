resource "digitalocean_tag" "manager" {
  name = "${var.swarm_env}-docker-swarm-manager"
}

resource "digitalocean_tag" "worker" {
  name = "${var.swarm_env}-docker-swarm-worker"
}

resource "digitalocean_tag" "postgres" {
  name = "${var.swarm_env}-docker-swarm-postgres"
}

resource "digitalocean_tag" "docker-swarm-env" {
  name = "${var.swarm_env}-docker-swarm"
}

resource "aws_s3_bucket" "docker-swarm-init-bucket" {
  bucket = "${var.swarm_env}.tokens.tmcloud.io"
  acl = "private"
  region = "${var.aws_region}"
  force_destroy = true
}

resource "digitalocean_volume" "postgres-storage" {
  name = "${var.swarm_env}-postgres-storage"
  region = "${var.do_region}"
  size = 100
}

resource "digitalocean_droplet" "manager-primary" {
  depends_on = [
    "digitalocean_tag.manager",
    "digitalocean_tag.docker-swarm-env",
    "aws_s3_bucket.docker-swarm-init-bucket"
  ]
  image = "${var.do_image}"
  name = "${var.swarm_env}-swarm-manager-leader"
  region = "${var.do_region}"
  size = "s-2vcpu-4gb"
  private_networking = true
  monitoring = true
  user_data = "#cloud-config\n\nssh_authorized_keys:\n — \"${file("${var.pub_key}")}\"\n"
  ssh_keys = [
    "${var.ssh_fingerprint}"
  ]
  connection {
    user = "root"
    type = "ssh"
    private_key = "${file(var.pvt_key)}"
    timeout = "2m"
  }
  provisioner "file" {
    source = "autoupdate/"
    destination = "/etc/apt/apt.conf.d"
  }
  provisioner "remote-exec" {
    scripts = [
      "provisioning/system-updates.sh",
      "provisioning/firewall.sh"
    ]
  }
  provisioner "file" {
    source = "swarmpit/"
    destination = "/usr/local/src"
  }
  provisioner "remote-exec" {
    inline = [
      <<EOF
        docker run -a STDOUT -a STDERR --restart on-failure:5 \
          -e SWARM_DISCOVERY_BUCKET=${aws_s3_bucket.docker-swarm-init-bucket.bucket} \
          -e ROLE=manager \
          -e NODE_IP=${self.ipv4_address_private} \
          -e AWS_ACCESS_KEY_ID=${var.swarm_discovery_s3_access_key_id} \
          -e AWS_SECRET_ACCESS_KEY=${var.swarm_discovery_s3_secret_key} \
          -e AWS_REGION=${var.aws_region} \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init > /dev/null
EOF
      , # install S3FS volume driver
      "docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.aws_region}",
      "docker stack deploy -c /usr/local/src/docker-compose.yml swarmpit"
    ]
  }
  tags = ["${digitalocean_tag.manager.name}", "${digitalocean_tag.docker-swarm-env.name}"]
}

resource "digitalocean_droplet" "manager-replica" {
  depends_on = [
    "digitalocean_droplet.worker",
    "digitalocean_droplet.postgres"
  ]
  count = "${var.swarm_manager_replicas_count}"
  image = "${var.do_image}"
  name = "${var.swarm_env}-swarm-manager-${count.index}"
  region = "${var.do_region}"
  size = "s-2vcpu-4gb"
  private_networking = true
  monitoring = true
  user_data = "#cloud-config\n\nssh_authorized_keys:\n — \"${file("${var.pub_key}")}\"\n"
  ssh_keys = [
    "${var.ssh_fingerprint}"
  ]
  connection {
    user = "root"
    type = "ssh"
    private_key = "${file(var.pvt_key)}"
    timeout = "2m"
  }
  provisioner "file" {
    source = "autoupdate/"
    destination = "/etc/apt/apt.conf.d"
  }
  provisioner "remote-exec" {
    scripts = [
      "provisioning/system-updates.sh",
      "provisioning/firewall.sh"
    ]
  }
  provisioner "remote-exec" {
    inline = [
      <<EOF
        docker run -a STDOUT -a STDERR --restart on-failure:5 \
          -e SWARM_DISCOVERY_BUCKET=${aws_s3_bucket.docker-swarm-init-bucket.bucket} \
          -e ROLE=manager \
          -e NODE_IP=${self.ipv4_address_private} \
          -e AWS_ACCESS_KEY_ID=${var.swarm_discovery_s3_access_key_id} \
          -e AWS_SECRET_ACCESS_KEY=${var.swarm_discovery_s3_secret_key} \
          -e AWS_REGION=${var.aws_region} \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init > /dev/null
EOF
      , # install S3FS volume driver
      "docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.aws_region}"
    ]
  }
  provisioner "remote-exec" {
    inline = "${formatlist("docker node update --label-add io.tmcloud.role=app %s", digitalocean_droplet.worker.*.name)}"
  }
  provisioner "remote-exec" {
    inline = "${formatlist("docker node update --label-add io.tmcloud.role=postgres %s", digitalocean_droplet.postgres.*.name)}"
  }
  tags = ["${digitalocean_tag.manager.name}", "${digitalocean_tag.docker-swarm-env.name}"]
}

resource "digitalocean_droplet" "worker" {
  depends_on = ["digitalocean_droplet.manager-primary"]
  count = "${var.swarm_workers_count}"
  image = "${var.do_image}"
  name = "${var.swarm_env}-swarm-worker-${count.index}"
  region = "${var.do_region}"
  size = "s-4vcpu-8gb"
  private_networking = true
  monitoring = true
  user_data = "#cloud-config\n\nssh_authorized_keys:\n — \"${file("${var.pub_key}")}\"\n"
  ssh_keys = [
    "${var.ssh_fingerprint}"
  ]
  connection {
    user = "root"
    type = "ssh"
    private_key = "${file(var.pvt_key)}"
    timeout = "2m"
  }
  provisioner "file" {
    source = "autoupdate/"
    destination = "/etc/apt/apt.conf.d"
  }
  provisioner "remote-exec" {
    scripts = [
      "provisioning/system-updates.sh",
      "provisioning/firewall.sh"
    ]
  }
  provisioner "remote-exec" {
    inline = [
      <<EOF
        docker run -a STDOUT -a STDERR --restart on-failure:5 \
          -e SWARM_DISCOVERY_BUCKET=${aws_s3_bucket.docker-swarm-init-bucket.bucket} \
          -e ROLE=worker \
          -e NODE_IP=${self.ipv4_address_private} \
          -e AWS_ACCESS_KEY_ID=${var.swarm_discovery_s3_access_key_id} \
          -e AWS_SECRET_ACCESS_KEY=${var.swarm_discovery_s3_secret_key} \
          -e AWS_REGION=${var.aws_region} \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init > /dev/null
EOF
      , # install S3FS volume driver
      "docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.aws_region}"
    ]
  }
  tags = ["${digitalocean_tag.worker.name}", "${digitalocean_tag.docker-swarm-env.name}"]
}

resource "digitalocean_droplet" "postgres" {
  depends_on = [
    "digitalocean_volume.postgres-storage",
    "digitalocean_droplet.manager-primary"
  ]
  count = 1
  image = "${var.do_image}"
  name = "${var.swarm_env}-swarm-postgres-worker-${count.index}"
  region = "${var.do_region}"
  size = "s-4vcpu-8gb"
  private_networking = true
  monitoring = true
  volume_ids = ["${digitalocean_volume.postgres-storage.id}"]
  user_data = "#cloud-config\n\nssh_authorized_keys:\n — \"${file("${var.pub_key}")}\"\n"
  ssh_keys = [
    "${var.ssh_fingerprint}"
  ]
  connection {
    user = "root"
    type = "ssh"
    private_key = "${file(var.pvt_key)}"
    timeout = "2m"
  }
  provisioner "file" {
    source = "autoupdate/"
    destination = "/etc/apt/apt.conf.d"
  }
  provisioner "remote-exec" {
    scripts = [
      "provisioning/system-updates.sh",
      "provisioning/firewall.sh"
    ]
  }
  provisioner "remote-exec" {
    inline = [
      <<EOF
        docker run -a STDOUT -a STDERR --restart on-failure:5 \
          -e SWARM_DISCOVERY_BUCKET=${aws_s3_bucket.docker-swarm-init-bucket.bucket} \
          -e ROLE=worker \
          -e NODE_IP=${self.ipv4_address_private} \
          -e AWS_ACCESS_KEY_ID=${var.swarm_discovery_s3_access_key_id} \
          -e AWS_SECRET_ACCESS_KEY=${var.swarm_discovery_s3_secret_key} \
          -e AWS_REGION=${var.aws_region} \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init > /dev/null
EOF
    , # install S3FS volume driver
      "docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.aws_region}",
      # Format DO Volume
      "sudo mkfs.ext4 -F /dev/disk/by-id/scsi-0DO_Volume_${digitalocean_volume.postgres-storage.name}",
      # Mount DO Volume
      "sudo mkdir -p /mnt/postgres-storage",
      "sudo mount -o discard,defaults /dev/disk/by-id/scsi-0DO_Volume_${digitalocean_volume.postgres-storage.name} /mnt/postgres-storage",
      "echo /dev/disk/by-id/scsi-0DO_Volume_${digitalocean_volume.postgres-storage.name} /mnt/postgres-storage ext4 defaults,nofail,discard 0 0 | sudo tee -a /etc/fstab",
      "sudo mkdir -p /mnt/postgres-storage/pg-data"
    ]
  }
  tags = ["${digitalocean_tag.postgres.name}", "${digitalocean_tag.docker-swarm-env.name}"]
}

resource "digitalocean_loadbalancer" "loadbalancer" {
  depends_on = ["digitalocean_droplet.worker"]
  "forwarding_rule" {
    entry_port = 80
    entry_protocol = "http"
    target_port = 80
    target_protocol = "http"
  }
  "forwarding_rule" {
    entry_port = 443
    entry_protocol = "https"
    target_port = 443
    target_protocol = "https"
    tls_passthrough = true
  }
  "forwarding_rule" {
    entry_port = 888
    entry_protocol = "http"
    target_port = 888
    target_protocol = "http"
  }
  healthcheck {
    port = 888
    protocol = "http"
    path = "/"
  }
  name = "${var.swarm_env}-swarm-loadbalancer"
  region = "${var.do_region}"
  droplet_tag = "${digitalocean_tag.docker-swarm-env.name}"
}

data "aws_route53_zone" "selected" {
  name = "tmcloud.io."
}

resource "aws_route53_record" "swarm-loadbalancer" {
  depends_on = ["digitalocean_loadbalancer.loadbalancer"]
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name = "${var.swarm_env}.${data.aws_route53_zone.selected.name}"
  type = "A"
  ttl = "300"
  records = ["${digitalocean_loadbalancer.loadbalancer.ip}"]
}

resource "aws_route53_record" "wildcard-record" {
  depends_on = ["aws_route53_record.swarm-loadbalancer"]
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name = "*.${var.swarm_env}.${data.aws_route53_zone.selected.name}"
  type = "CNAME"
  ttl = "300"
  records = ["${aws_route53_record.swarm-loadbalancer.name}"]
}
