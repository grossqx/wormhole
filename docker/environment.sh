#!/bin/bash

TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
STORAGE_PATH="${docker_volumes}"
STACKS_DIR="${docker_stacks}"
CONFIG_DIR="${docker_configs}"
PUID=$(id -u wormhole)
PGID=$(id -g wormhole)
SERVER_NAME=$(hostname)
WEBPASSWORD="changeme"

# VPN
WIREGUARD_PORT=$WH_WIREGUARD_PORT
WIREGUARD_UI_PORT=8888
PIHOLE_UI_PORT=8180
WIREGUARD_URL="${WH_DOMAIN##*://}"
VPN_SUBNET=10.2.0.0/24
UNBOUND_IP=10.2.0.2
PIHOLE_IP=10.2.0.3
WIREGUARD_IP=10.2.0.4