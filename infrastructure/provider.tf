variable "do_token" {}
variable "do_region" {
  default = "fra1"
}
variable "do_image" {
  default = "ubuntu-18-04-x64"
}

variable "pub_key" {}
variable "pvt_key" {}
variable "ssh_fingerprint" {}

variable "swarm_env" {
  default = "test"
}
variable "swarm_manager_replicas_count" {
  default = 1
}
variable "swarm_workers_count" {
  default = 1
}
variable "swarm_discovery_s3_bucket" {}
variable "swarm_discovery_s3_access_key_id" {}
variable "swarm_discovery_s3_secret_key" {}
variable "swarm_discovery_s3_region" {
  default = "eu-central-1"
}

variable "volumes_s3_access_key_id" {}
variable "volumes_s3_secret_key" {}
variable "volumes_s3_region" {
  default = "eu-central-1"
}

provider "digitalocean" {
  token = "${var.do_token}"
}
