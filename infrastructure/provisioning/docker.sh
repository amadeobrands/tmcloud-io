#!/usr/bin/env bash

sudo rm /var/lib/apt/lists/* -vf
sudo apt update

sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic test"

sudo rm /var/lib/apt/lists/* -vf
sudo apt update

sudo apt install -y docker-ce

sudo systemctl start docker
sudo systemctl enable docker

docker --version
