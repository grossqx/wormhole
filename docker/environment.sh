#!/bin/bash

TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
STORAGE_PATH="$docker_volumes"
STACKS_DIR="${docker_configs}/stacks"
CONFIG_DIR="${docker_configs}/configs"
PUID=$(id -u wormhole)
PGID=$(id -g wormhole)
SERVER_NAME=$(hostname)
WEBPASSWORD="wormhole"

# VPN
WIREGUARD_UI_PORT=8888
WIREGUARD_PORT=51820
PIHOLE_UI_PORT=8180
WIREGUARD_URL="${WH_DOMAIN##*://}"