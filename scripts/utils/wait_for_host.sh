#!/bin/bash

RPI_HOST=$1
TIMEOUT=$2
DEVICE_NAME=$3

if [[ -z "$DEVICE_NAME" ]]; then
    DEVICE_NAME="Raspberry Pi"
fi

## Text colors:
source ${base_dir}/res/theme.env

echo "Waiting for ${DEVICE_NAME} at ${RPI_HOST} ..."

# Custom message for Raspberry Pi
if [[ $DEVICE_NAME == "Raspberry Pi" ]]; then
    echo -e "${T_BLUE}Please ensure the Raspberry Pi is powered on and connected to the network...${T_NC}"
fi

start_time=$(date +%s)

timeout_minutes=$(( TIMEOUT / 60 ))
timeout_seconds=$(( TIMEOUT % 60 ))
timeout_formatted=$(printf "%02d:%02d" $timeout_minutes $timeout_seconds)

while true; do
    elapsed_time=$(( $(date +%s) - start_time ))
    minutes=$(( elapsed_time / 60 ))
    seconds=$(( elapsed_time % 60 ))
    formatted_time=$(printf "%02d:%02d" $minutes $seconds)
    ping -c 1 -W 1 "$RPI_HOST" &> /dev/null
    if [[ $? -eq 0 ]]; then
        break
    fi
    printf "\r\033[K${T_YELLOW}Status: waiting for %s to appear online...${T_NC} (time elapsed: %s / %s)" "${DEVICE_NAME}" "${formatted_time}" "${timeout_formatted}"
    if [[ $elapsed_time -gt $TIMEOUT ]]; then
        echo -e "\n${T_RED}Timeout reached. ${DEVICE_NAME} is not reachable.${T_NC}"
        exit 1
    fi
    sleep 1s
done

online_time=$(date +"%H:%M:%S")
elapsed_time=$(( $(date +%s) - start_time ))

minutes=$(( elapsed_time / 60 ))
seconds=$(( elapsed_time % 60 ))
formatted_time=$(printf "%02d:%02d" $minutes $seconds)

printf "\r\033[K${T_GREEN}Status: %s online since %s.${T_NC} (time elapsed: %s)\n" "${DEVICE_NAME}" "${online_time}" "${formatted_time}"
exit 0