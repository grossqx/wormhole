#!/bin/bash

## Text colors:
source ${base_dir}/res/theme.env

binary_name="$1"
persistent_data_dir="$2"
app_name="$3"

echo -e "${T_BOLD}${app_name}${T_NC}"
echo -e "${T_ITALIC}This script was just downloaded from the server and installed locally.${T_NC}"
echo -e "${T_BLUE}Info:${T_NC}"
echo -e "${T_ITALIC}All installed files are located in ${base_dir} and take up $(du -sh ${base_dir} | awk {'print $1'})${T_NC}"
echo -e "${T_ITALIC}All scripts inside directories /utils and /rpi are meant to be used by ${binary_name} only, not by the user.${T_NC}"
echo -e "${T_ITALIC}Persistent user data and the OS images are is stored in ${persistent_data_dir}${T_NC}"
