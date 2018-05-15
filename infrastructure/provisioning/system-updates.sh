#!/bin/bash

unset UCF_FORCE_CONFFOLD
export UCF_FORCE_CONFFNEW=YES
ucf --purge /boot/grub/menu.lst

export DEBIAN_FRONTEND=noninteractive

sudo -E systemctl stop apt-daily.timer > /dev/null
sudo -E apt-get clean  > /dev/null
echo "Updating packages..."
sudo -E apt-get update > /dev/null
sudo -E apt-get install unattended-upgrades > /dev/null
echo "Upgrading packages..."
sudo -E apt-get upgrade -y  > /dev/null
echo "Upgrading distro..."
sudo -E apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade > /dev/null
sudo -E systemctl start apt-daily.timer > /dev/null
