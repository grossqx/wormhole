#!/bin/bash

## Text colors:
source ${base_dir}/res/theme.env

binary_name="$1"
persistent_data_dir="$2"
app_name="$3"

echo -e "${T_BOLD}${app_name}${T_NC}"
echo -e "${T_ITALIC}Script was successfully downloaded the from the server and installed locally.${T_NC}"
echo -e "${T_BLUE}Information:${T_NC}"
echo -e "${T_ITALIC}Scripts inside the install directory are not meant to be run manually by the user.${T_NC}"
echo -e "To see options run ${T_ITALIC}${binary_name} --help${T_NC}"
echo -e "All installed files are located in ${T_ITALIC}${base_dir}${T_NC} and take up $(du -sh ${base_dir} | awk {'print $1'})."
echo -e "   OS images are is stored in ${T_ITALIC}$HOME/.cache/wormhole${T_NC}"
echo -e " Persistent data is stored in ${T_ITALIC}${persistent_data_dir}${T_NC}"
