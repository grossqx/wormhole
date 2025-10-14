#!/bin/bash

set -e
set -o pipefail

## Text colors:
source ${base_dir}/res/theme.env

CONNECT_TIMEOUT=60
MAX_TIME=120

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <config_file_path> <api_url> <api_key>"
    exit 1
fi

CONFIG_PATH="$1"
API_URL="$2"
API_KEY="$3"

if [ -f "$CONFIG_PATH" ]; then
    source "$CONFIG_PATH"
else
    echo -e "${T_RED}Error: Configuration file not found at ${CONFIG_PATH}${T_NC}"
    exit 1
fi

TIME_CREATION=$(date +%s)
PAYLOAD_JSON=$(jq --null-input \
            --arg install_id "$install_id" \
            --arg hardware_api_key "$RPI_HARDWARE_API_KEY" \
            --arg config_name "$RPI_CONFIG_NAME" \
            --argjson time_creation "$TIME_CREATION" \
            --arg hostname "$RPI_HOSTNAME" \
            --arg ip_address "$RPI_IP_ADDR" \
            --arg domain "$RPI_DOMAIN" \
            --arg wh_port "$RPI_WH_PORT" \
            '{
                "install-id": $install_id,
                "hardware-api-key": $hardware_api_key,
                "config-name": $config_name,
                "time-creation": $time_creation,
                "hostname": $hostname,
                "ip-address": $ip_address,
                "domain": $domain,
                "wh-port": $wh_port
            }')
ENCRYPTED_PAYLOAD=$(printf "%s" "$PAYLOAD_JSON" | openssl enc "${crypto_cipher}" "${key_derivation}" -a -e -salt -pass pass:"${crypto_key}")
if [ $? -ne 0 ]; then
    echo -e "${T_RED}Error: Encryption failed.${T_NC}"
    exit 1
fi

echo -e "${T_BLUE}Sending data to the API Server...${T_NC}"

RESPONSE=$(curl --show-error --silent --write-out "\nHTTP_STATUS:%{http_code}" \
  --connect-timeout "$CONNECT_TIMEOUT" \
  --max-time "$MAX_TIME" \
  -X POST "$API_URL" \
  -H "Content-Type: text/plain" \
  -H "Authorization: Bearer $API_KEY" \
  --data-binary "$ENCRYPTED_PAYLOAD")

HTTP_BODY=$(echo "$RESPONSE" | sed '$ d')
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1 | cut -d: -f2)

case $? in
    0)
        # HTTP request successful, proceed with jq parsing
        ;;
    6)
        echo -e "${T_RED}Error: Could not resolve host '$API_URL'.${T_NC}"
        exit 1
        ;;
    28)
        echo -e "${T_RED}Error: Connection timed out. The server did not respond within the allowed time.${T_NC}"
        exit 1
        ;;
    *)
        echo -e "${T_RED}Error: HTTP request failed with an unexpected code. Exit code: $?${T_NC}"
        exit 1
        ;;
esac

SUCCESS=$(echo "$HTTP_BODY" | jq -r '.success')

if [ "$SUCCESS" = "true" ]; then
    echo -e "HTTP Status: ${HTTP_STATUS}"
    echo -e "${T_GREEN}Configuration data was received on the server side${T_NC}"
    exit 0
else
    ERROR_MESSAGE=$(echo "$HTTP_BODY" | jq -r '.status')
    echo -e "HTTP Status: ${HTTP_STATUS}"
    echo -e "${T_RED}Error: ${ERROR_MESSAGE}${T_NC}"
    exit 1
fi
