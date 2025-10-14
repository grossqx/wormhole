#!/bin/bash

set -e

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <config_file_path> <template_script> <output_script>"
    exit 1
fi

CONFIG_FILE="$1"
TEMPLATE_FILE="$2"
OUTPUT_FILE="$3"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found."
    exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file '$TEMPLATE_FILE' not found."
    exit 1
fi

# Source the configuration file to load variables
source "$CONFIG_FILE"

cp "$TEMPLATE_FILE" "$OUTPUT_FILE"

# Use sed to replace the variables in the copied file
sed -i "s|WIFI_SSID=\"\"|WIFI_SSID=\"${RPI_WIFI_SSID}\"|g" "$OUTPUT_FILE"
sed -i "s|WIFI_PASS=\"\"|WIFI_PASS=\"${RPI_WIFI_PASSWORD}\"|g" "$OUTPUT_FILE"
sed -i "s|WIFI_LOC=\"\"|WIFI_LOC=\"${RPI_WIFI_LOC}\"|g" "$OUTPUT_FILE"

sed -i "s|SSH_USER=\"\"|SSH_USER=\"${RPI_SSH_USER}\"|g" "$OUTPUT_FILE"
sed -i "s|SSH_PASS=\"\"|SSH_PASS=\"${RPI_SSH_PASSWORD}\"|g" "$OUTPUT_FILE"
sed -i "s|SSH_PORT=\"\"|SSH_PORT=\"${RPI_SSH_PORT}\"|g" "$OUTPUT_FILE"

sed -i "s|HOSTNAME=\"\"|HOSTNAME=\"${RPI_HOSTNAME}\"|g" "$OUTPUT_FILE"
sed -i "s|TIMEZONE=\"\"|TIMEZONE=\"${RPI_TIMEZONE}\"|g" "$OUTPUT_FILE"

sed -i "s|WH_INSTALL_ID=\"\"|WH_INSTALL_ID=\"${install_id}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_INSTALL_CONFIG=\"\"|WH_INSTALL_CONFIG=\"${RPI_CONFIG_NAME}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_INSTALL_USER=\"\"|WH_INSTALL_USER=\"${install_user}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_INSTALL_USER_IP=\"\"|WH_INSTALL_USER_IP=\"${install_user_ip}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_SERVER_API_URL=\"\"|WH_SERVER_API_URL=\"${api_domain}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_HARDWARE_API_KEY=\"\"|WH_HARDWARE_API_KEY=\"${RPI_HARDWARE_API_KEY}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_CRYPTO_DERIVATION=\"\"|WH_CRYPTO_DERIVATION=\"${key_derivation}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_CRYPTO_CIPHER=\"\"|WH_CRYPTO_CIPHER=\"${crypto_cipher}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_CRYPTO_KEY=\"\"|WH_CRYPTO_KEY=\"${crypto_key}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_IP_ADDR=\"\"|WH_IP_ADDR=\"${RPI_IP_ADDR}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_DOMAIN=\"\"|WH_DOMAIN=\"${RPI_DOMAIN}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_WIREGUARD_PORT=\"\"|WH_WIREGUARD_PORT=\"${RPI_WH_PORT}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_PATH=\"\"|WH_PATH=\"${distro_dir}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_BOOT_DEVICE=\"\"|WH_BOOT_DEVICE=\"${RPI_BOOT_DEVICE}\"|g" "$OUTPUT_FILE"
sed -i "s|WH_BOOT_DEVICE2=\"\"|WH_BOOT_DEVICE2=\"${RPI_BOOT_DEVICE2}\"|g" "$OUTPUT_FILE"

# Pack scripts into firstrun.sh
source ${base_dir}/common/embed_extract_files.sh
manifest="${base_dir}/rpi/update.manifest.json"

for file_id in $(jq -r '.files | keys | .[]' "$manifest"); do
    source=$(jq -r ".files.\"$file_id\".source" "$manifest")
    path=$(jq -r ".files.\"$file_id\".path" "$manifest")
    embed_file ".$source" "$OUTPUT_FILE" "$file_id" "$path"
done
