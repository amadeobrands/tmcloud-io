#!/usr/bin/env bash

echo "Setting up Firewall"

yes | ufw enable

ufw allow out 80
ufw allow out 443
ufw allow out 53

ufw allow 22/tcp
ufw allow 2376/tcp
ufw allow 2377/tcp
ufw allow 7946/tcp
ufw allow 7946/udp
ufw allow 4789/udp

ufw reload
