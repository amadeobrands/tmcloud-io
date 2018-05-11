variable "do_token" {}

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

variable "volumes_s3_access_key_id" {}
variable "volumes_s3_secret_key" {}
variable "volumes_s3_region" {}

provider "digitalocean" {
  token = "${var.do_token}"
}
