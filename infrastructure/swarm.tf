resource "digitalocean_tag" "manager" {
  name = "${var.swarm_env}-docker-swarm-manager"
}

resource "digitalocean_tag" "worker" {
  name = "${var.swarm_env}-docker-swarm-worker"
}

resource "digitalocean_tag" "docker-swarm-env" {
  name = "${var.swarm_env}-docker-swarm"
}

resource "digitalocean_droplet" "manager-primary" {
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
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade"
    ]
  }
  provisioner "remote-exec" {
    scripts = [
      "provisioning/firewall.sh",
      "provisioning/docker.sh"
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
          -e SWARM_DISCOVERY_BUCKET=${var.swarm_discovery_s3_bucket} \
          -e ROLE=manager \
          -e NODE_IP=${self.ipv4_address_private} \
          -e AWS_ACCESS_KEY_ID=${var.swarm_discovery_s3_access_key_id} \
          -e AWS_SECRET_ACCESS_KEY=${var.swarm_discovery_s3_secret_key} \
          -e AWS_REGION=${var.swarm_discovery_s3_region} \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init
EOF
      , # install S3FS volume driver
      "docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.volumes_s3_region}",
      "docker stack deploy -c /usr/local/src/docker-compose.yml swarmpit"
    ]
  }
  tags = ["${var.swarm_env}-docker-swarm-manager", "${var.swarm_env}-docker-swarm"]
}


resource "digitalocean_droplet" "manager-replica" {
  depends_on = ["digitalocean_droplet.manager-primary"]
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
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade"
    ]
  }
  provisioner "remote-exec" {
    scripts = [
      "provisioning/firewall.sh",
      "provisioning/docker.sh"
    ]
  }
  provisioner "remote-exec" {
    inline = [
      <<EOF
        docker run -a STDOUT -a STDERR --restart on-failure:5 \
          -e SWARM_DISCOVERY_BUCKET=${var.swarm_discovery_s3_bucket} \
          -e ROLE=manager \
          -e NODE_IP=${self.ipv4_address_private} \
          -e AWS_ACCESS_KEY_ID=${var.swarm_discovery_s3_access_key_id} \
          -e AWS_SECRET_ACCESS_KEY=${var.swarm_discovery_s3_secret_key} \
          -e AWS_REGION=${var.swarm_discovery_s3_region} \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init
EOF
      , # install S3FS volume driver
      "docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.volumes_s3_region}"
    ]
  }
  tags = ["${var.swarm_env}-docker-swarm-manager", "${var.swarm_env}-docker-swarm"]
}


resource "digitalocean_droplet" "worker" {
  depends_on = ["digitalocean_droplet.manager-replica"]
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
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade"
    ]
  }
  provisioner "remote-exec" {
    scripts = [
      "provisioning/firewall.sh",
      "provisioning/docker.sh"
    ]
  }
  provisioner "remote-exec" {
    inline = [
      <<EOF
        docker run -a STDOUT -a STDERR --restart on-failure:5 \
          -e SWARM_DISCOVERY_BUCKET=${var.swarm_discovery_s3_bucket} \
          -e ROLE=worker \
          -e NODE_IP=${self.ipv4_address_private} \
          -e AWS_ACCESS_KEY_ID=${var.swarm_discovery_s3_access_key_id} \
          -e AWS_SECRET_ACCESS_KEY=${var.swarm_discovery_s3_secret_key} \
          -e AWS_REGION=${var.swarm_discovery_s3_region} \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init
EOF
      , # install S3FS volume driver
      "docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.volumes_s3_region}"
    ]
  }
  tags = ["${var.swarm_env}-docker-swarm-worker", "${var.swarm_env}-docker-swarm"]
}


resource "digitalocean_loadbalancer" "loadbalancer" {
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
  droplet_tag = "${var.swarm_env}-docker-swarm-worker"
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
