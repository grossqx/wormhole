#!/bin/bash

service_name="wormholed.service"
report_interval=60
declare -a TEST_HOSTS=("isc.org" "google.com" "cloudflare.com" "1.1.1.1" "8.8.8.8")

# Service management and systemd reports
function sdreport(){
    local message="$1"
    systemd-notify --status="$message"
}

function sdreport_ready() {
    local message="$1"
    systemd-notify --status="$message" --ready
}

function sdreport_stopping_soon() {
    local message="$1"
    systemd-notify --status="$message" --stopping
}

function sdreport_failure() {
    local message="$1"
    local error_code="$2"
    local errno_flag=""
    if [[ -n "$error_code" ]]; then
        errno_flag="--errno=\"$error_code\""
    fi
    systemd-notify --status="$message" --ready $errno_flag
    exit 1
}

function sdreport_success() {
    local message="$1"
    systemd-notify --status="$message" --ready
    exit 0
}

function main_loop(){
    # Send telemetry to the server
    wh_send_payload "$(rpi-sysinfo --json)" "${WH_SERVER_API_URL}/wh/telemetry"
}

function check_internet() {
    local host
    local retry_count=0
    local MAX_RETRIES=3
    local RETRY_DELAY=5
    while [ "$retry_count" -lt "$MAX_RETRIES" ]; do
        for host in "${TEST_HOSTS[@]}"; do
            if ping -c 1 -W 3 "$host" > /dev/null 2>&1; then
                return 0
            fi
        done
        retry_count=$((retry_count + 1))        
        if [ "$retry_count" -lt "$MAX_RETRIES" ]; then
            sleep "$RETRY_DELAY"
        fi
    done
    return 1
}

function is_ethernet_active() {
    ETH_IFACES=$(ip addr show | awk -F: '/: e/{print $2}' | tr -d ' ')
    for IFACE in $ETH_IFACES; do
        if ip addr show dev "$IFACE" | grep -q "inet "; then
            return 0
        fi
    done
    return 1
}

function is_wifi_blocked() {
    rfkill list wifi | grep -q "Soft blocked: yes"
    return $?
}

# Files to be sourced
dependencies=(
    "/etc/environment"
    "/etc/profile.d/rpi_sysinfo.sh"
    "/etc/profile.d/wh_logger.sh"
    "/etc/profile.d/wh_storage.sh"
)

# Required environment variables
required_vars=(
    "WH_INSTALL_ID"
    "WH_INSTALL_CONFIG"
    "WH_INSTALL_USER"
    "WH_INSTALL_USER_IP"
    "WH_SERVER_API_URL"
    "WH_HARDWARE_API_KEY"
    "WH_CRYPTO_KEY"
    "WH_IP_ADDR"
    "WH_DOMAIN"
    "WH_WIREGUARD_PORT"
    "WH_PATH"
    "WH_HOME"
    "WH_LOG_FILE"
    "WH_BOOT_DEVICE"
    "WH_BOOT_DEVICE2"
)

# Required functions
required_functions=(
    "rpi-sysinfo"
    "wh_log_local"
    "wh_log_remote"
    "wh_log"
    "wh-storage-resolve"
)

# Check requirements before initialization
error_occurred=false
initialization_errors=""
# Check for and source configuration files
for file in "${dependencies[@]}"; do
    if [[ -f "$file" ]]; then
        . "$file"
    else
        initialization_errors+="Missing file: $file\n"
        error_occurred=true
    fi
done
# Loop through the variables and check if they are set and not empty
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        initialization_errors+="Missing variable: $var\n"
        error_occurred=true
    fi
done
# Loop through the functions and check if they are defined
for func in "${required_functions[@]}"; do
    if ! type -t "$func" >/dev/null; then
        initialization_errors+="Missing function: $func\n"
        error_occurred=true
    fi
done

# Report on state
if [[ $error_occurred == "true" ]]; then
    echo -e "Configuration check failed:\n$initialization_errors"
    sdreport_ready_failure "Core Wormhole library is missing" "2" #ERRNO 2 - Missing files or directiories
else
    sdreport_ready "Started"
fi

# Test internet connection. 
check_internet
online=$?
if [[ $online -eq 0 ]]; then
    echo "Internet connection is confirmed."
    wh_log "Starting up ${service_name}"
    if is_ethernet_active; then
        echo "Connection is via Ethernet."
        if ! is_wifi_blocked; then
            echo "Action: Wi-Fi is currently enabled. Disabling to optimize power."
            wh_log "Wi-Fi is currently enabled. Disabling to optimize power."
            rfkill block wifi
        else
            echo "Wi-Fi is already disabled. No change needed."
        fi
    else
        echo "Internet is up, but no Ethernet link is active. Keeping Wi-Fi enabled."
    fi
else
    echo "Warning: Internet connection is currently DOWN."
    wh_log_local "Starting up ${service_name}"
    if is_wifi_blocked; then
        echo "Action: Wi-Fi is disabled and internet is down. Enabling Wi-Fi."
        wh_log_local "Wi-Fi is disabled and internet is down. Enabling Wi-Fi."
        rfkill unblock wifi
    else
        echo "Wi-Fi is already enabled. No change needed."
    fi
fi
#wh_log "Starting the 

# Check boot media
current_boot_path=$(mount | grep " / " | awk '{print $1}')
if [ -z $WH_BOOT_DEVICE ]; then
    echo "Warning: Primary boot device not set"
else
    resolved_device=$(wh-storage-resolve $WH_BOOT_DEVICE)
    if echo "$current_boot_path" | grep -q "$resolved_device"; then
        echo "Currently booted from the Primary device: ${resolved_device}"
        if [[ $online -eq 0 ]]; then
            wh_log "Currently booted from the Primary device: ${resolved_device}"
        else
            wh_log_local "Currently booted from the Primary device: ${resolved_device}"
        fi
    fi
fi
if [ -z $WH_BOOT_DEVICE2 ]; then
    echo "Warning: Secondary boot device not set"
else
    resolved_device2=$(wh-storage-resolve $WH_BOOT_DEVICE2)
    if echo "$current_boot_path" | grep -q "$resolved_device2"; then
        echo "Currently booted from the Secondary device: ${resolved_device}"
        if [[ $online -eq 0 ]]; then
            wh_log "Currently booted from the Secondary device: ${resolved_device}"
        else
            wh_log_local "Currently booted from the Secondary device: ${resolved_device}"
        fi
    fi
fi

main_loop

sudo $WH_PATH/wormhole.sh migrate-run

# Main loop
while true; do
    main_loop
    sleep $report_interval
done

sdreport_failure "Script loop unexpectedly finished."
