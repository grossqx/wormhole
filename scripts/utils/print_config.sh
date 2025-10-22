#!/bin/bash

CONFIG_PATH=$1
PRINT_TO_FILE=$2

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

if [[ -z $RPI_CONFIG_TAG ]]; then
    display_tag="<not set>"
else
    display_tag=$RPI_CONFIG_TAG
fi

if [[ -z $RPI_CONFIG_SEARCH ]]; then
    display_search="<not set>"
else
    display_search=$RPI_CONFIG_SEARCH
fi

if [[ -z $RPI_IP_ADDR ]]; then
    display_ip="<not set>"
else
    display_ip=$RPI_IP_ADDR
fi

if [[ -z $RPI_DOMAIN ]]; then
    display_domain="<not set>"
else
    display_domain=$RPI_DOMAIN
fi

echo -e  "==============================================================================="
echo -e "${T_BOLD}${RPI_CONFIG_NAME}${T_NC} - ${T_ITALIC}${RPI_DESCRIPTION}${T_NC}"
echo -e "\tdevice: ${T_BLUE}${display_tag}${T_NC} (query: ${T_BLUE}${display_search}${T_NC})"
echo -e "\tinternal IP address: ${T_BLUE}${display_ip}${T_NC} (domain ${T_BLUE}${display_domain}${T_NC})"
echo -e "\ttimezone: ${T_BLUE}${RPI_TIMEZONE}${T_NC}"
echo -e "\thostname: ${T_BLUE}${RPI_HOSTNAME}${T_NC}"
if [[ "$PRINT_TO_FILE" == "true" ]]; then
    echo -e "\thardware API key: ${T_BLUE}${RPI_HARDWARE_API_KEY}${T_NC}"
else
    echo -e "\thardware API key: ${T_BLUE}<hidden>${T_NC}"
fi
if [[ -n "$RPI_WIFI_SSID" ]]; then
    echo -e  "\tSSID: ${T_BLUE}${RPI_WIFI_SSID}${T_NC}"
    echo -e  "\tWiFi location: ${T_BLUE}${RPI_WIFI_LOC}${T_NC}"
    if [[ "$PRINT_TO_FILE" == "true" ]]; then
        echo -e  "\tWiFi password: ${T_BLUE}${RPI_WIFI_PASSWORD}${T_NC}"
    else
        echo -e  "\tWiFi password: ${T_BLUE}<hidden>${T_NC}"
    fi
else
    echo -e "${T_YELLOW}On-device Wifi Configuration not set by the configuration:${T_NC}"
    echo -e "${T_YELLOW}    This setup will only work if the device is connected with an Ethernet cable.${T_NC}" 
fi
if [[ -n "$RPI_SSH_USER" ]]; then
    echo -e  "\tssh user: ${T_BLUE}${RPI_SSH_USER}${T_NC}"
    echo -e  "\tssh port: ${T_BLUE}${RPI_SSH_PORT}${T_NC}"
    if [[ "$PRINT_TO_FILE" == "true" ]]; then
        echo -e  "\tssh password: ${T_BLUE}${RPI_SSH_PASSWORD}${T_NC}"
    else
        echo -e  "\tssh password: ${T_BLUE}<hidden>${T_NC}"
    fi
else
    echo -e "${T_YELLOW}On-device SSH Configuration not set by the configuration:${T_NC}"
    echo -e "${T_YELLOW}    Device will still be able to call home. But you will only be able to access it with a physical connection.${T_NC}"
fi
echo -e  "==============================================================================="
exit 0
