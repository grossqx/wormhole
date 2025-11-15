#!/bin/bash

CONFIG_PATH=$1
RPI_MAC=$2
PRINT_TO_FILE=$3

if [[ "$PRINT_TO_FILE" != "true" ]]; then
    source ${base_dir}/res/theme.env
else
    T_BOLD=""
    T_NC=""
    T_ITALIC=""
    T_BLUE=""
    T_YELLOW=""
fi

source "${CONFIG_PATH}"

if [[ -z $RPI_IP_ADDR ]]; then
    display_ip="< IP address picked by you >"
else
    display_ip=$RPI_IP_ADDR
fi

echo -e  "==============================================================================="
echo -e "${T_BOLD}Router configuration${T_NC} - ${T_ITALIC}these have to be configured manually${T_NC}"
echo -e "${T_BLUE}1. DHCP - static IP address:${T_NC}"
echo -e "\thostname: ${T_BLUE}${RPI_HOSTNAME}${T_NC}"
echo -e "\tinternal IP address: ${T_BLUE}${display_ip}${T_NC}" 
if [[ ! -z "$RPI_MAC" ]]; then
    echo -e "\tMAC: ${T_BLUE}${RPI_MAC}${T_NC}"
fi
echo -e "${T_BLUE}2. Port forwarding rules:${T_NC}"
echo -e "\tWireguard VPN: port ${T_BLUE}${RPI_WH_PORT}${T_NC} at ${T_BLUE}${display_ip}${T_NC} ${T_BLUE}(UDP protocol)${T_NC}" 
if [[ ! -z $RPI_DOMAIN ]]; then
    echo -e "${T_BLUE}3. DNS record ${T_NC}"
    echo -e "\tsource: ${T_BLUE}${RPI_DOMAIN}${T_NC}" 
    echo -e "\tdestination: ${T_BLUE}http://${display_ip}:${RPI_WH_PORT}${T_NC}" 
else
    echo -e "${T_YELLOW}3. DNS record not configured${T_NC}"
fi
echo -e  "==============================================================================="
exit 0
