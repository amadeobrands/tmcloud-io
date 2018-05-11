resource "digitalocean_tag" "manager" {
  name = "manager"
}

resource "digitalocean_tag" "worker" {
  name = "worker"
}

resource "digitalocean_tag" "docker-swarm-env" {
  name = "docker-swarm-${var.swarm_env}"
}

resource "digitalocean_droplet" "manager-primary" {
  image = "ubuntu-18-04-x64"
  name = "${var.swarm_env}-swarm-manager-primary"
  region = "fra1"
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
    source = "swarmpit/"
    destination = "/home/root"
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
          -e AWS_REGION=eu-central-1 \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init
EOF

      /*
      "sudo docker swarm init",
      "sudo docker swarm join-token --quiet manager > /home/ubuntu/manager-token",
      "sudo docker swarm join-token --quiet worker > /home/ubuntu/worker-token",

      # install S3FS volume driver
      "sudo docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.volumes_s3_region}"
      "sudo docker stack deploy -c /home/root/swarmpit/docker-compose.yml swarmpit"
      */
    ]
  }
  tags = ["manager", "docker-swarm-${var.swarm_env}"]
}


resource "digitalocean_droplet" "manager-replica" {
  depends_on = ["digitalocean_droplet.manager-primary"]
  count = "${var.swarm_manager_replicas_count}"
  image = "ubuntu-18-04-x64"
  name = "${var.swarm_env}-swarm-manager-${count.index}"
  region = "fra1"
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
          -e AWS_REGION=eu-central-1 \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init
EOF
      # install S3FS volume driver
      # "sudo docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.volumes_s3_region}"
    ]
  }
  tags = ["manager", "docker-swarm-${var.swarm_env}"]
}


resource "digitalocean_droplet" "worker" {
  depends_on = ["digitalocean_droplet.manager-primary"]
  count = "${var.swarm_workers_count}"
  image = "ubuntu-18-04-x64"
  name = "${var.swarm_env}-swarm-worker-${count.index}"
  region = "fra1"
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
          -e AWS_REGION=eu-central-1 \
          -v /var/run/docker.sock:/var/run/docker.sock \
          mrjgreen/aws-swarm-init
EOF
      # install S3FS volume driver
      #"sudo docker plugin install --grant-all-permissions rexray/s3fs S3FS_ACCESSKEY=${var.volumes_s3_access_key_id} S3FS_SECRETKEY=${var.volumes_s3_secret_key} S3FS_REGION=${var.volumes_s3_region}"
    ]
  }
  tags = ["worker", "docker-swarm-${var.swarm_env}"]
}

