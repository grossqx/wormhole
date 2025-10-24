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

check_new_boot_devices() {
    local WH_DISKS_FILE="${WH_HOME}/.disks"
    local CURRENT_DISKS_TEMP=$(mktemp)
    # trap "rm -f \"$CURRENT_DISKS_TEMP\"" EXIT HUP INT TERM
    lsblk -d -n -o NAME 2>/dev/null > "$CURRENT_DISKS_TEMP"
    if [ ! -f "$WH_DISKS_FILE" ]; then
        echo "Disk state file not found. Creating baseline at $WH_DISKS_FILE."
        mv "$CURRENT_DISKS_TEMP" "$WH_DISKS_FILE"
        return 1
    fi
    if ! diff -q "$WH_DISKS_FILE" "$CURRENT_DISKS_TEMP" >/dev/null; then
        NEW_DEVICES=$(grep -Fxv -f "$WH_DISKS_FILE" "$CURRENT_DISKS_TEMP")
        if [ -n "$NEW_DEVICES" ]; then
            echo "New devices detected:"
            echo "$NEW_DEVICES" | while IFS= read -r device_name; do
                device_path="/dev/$device_name"
                echo "$device_path"
            done
            mv "$CURRENT_DISKS_TEMP" "$WH_DISKS_FILE"
            return 0
        fi

        DISCONNECTED_DEVICES=$(grep -Fxv -f "$CURRENT_DISKS_TEMP" "$WH_DISKS_FILE")
        if [ -n "$DISCONNECTED_DEVICES" ]; then
            echo "Disconnected devices:"
            echo "$DISCONNECTED_DEVICES" | while IFS= read -r device_name; do
                device_path="/dev/$device_name"
                echo "$device_path"
            done
            mv "$CURRENT_DISKS_TEMP" "$WH_DISKS_FILE"
            return 1
        fi
        mv "$CURRENT_DISKS_TEMP" "$WH_DISKS_FILE" # Fallback
        echo "Error: Device state changed, but could not classify case. State updated."
        return 1
    else
        echo "No block device changes detected."
        return 1
    fi
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
    "WH_CRYPTO_DERIVATION"
    "WH_CRYPTO_CIPHER"
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
wifi_message=""
check_internet
online=$?
if [[ $online -eq 0 ]]; then
    wifi_message="${wifi_message}Internet connection active. "
    if is_ethernet_active; then
        wifi_message="${wifi_message}Connected via Ethernet. "
        if ! is_wifi_blocked; then
            wifi_message="${wifi_message}Wi-Fi currently enabled. Disabling to optimize power. "
            rfkill block wifi
        else
            wifi_message="${wifi_message}Wi-Fi already disabled. No change needed. "
        fi
    else
        wifi_message="${wifi_message}No Ethernet link is active. Keeping Wi-Fi enabled. "
    fi
else
    wifi_message="${wifi_message}Warning: Internet connection is currently DOWN. "
    if is_wifi_blocked; then
        wifi_message="${wifi_message}Enabling Wi-Fi. "
        rfkill unblock wifi
    else
        wifi_message="${wifi_message}Wi-Fi already enabled. No change needed. "
    fi
fi

wh_log "Starting up ${service_name}"
wh_log "${wifi_message}"

# Check boot media
current_boot_path=$(mount | grep " / " | awk '{print $1}')
if [ -z $WH_BOOT_DEVICE ]; then
    echo "Warning: Primary boot device not set"
else
    resolved_device=$(wh-storage-resolve $WH_BOOT_DEVICE)
    if echo "$current_boot_path" | grep -q "$resolved_device"; then
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
        if [[ $online -eq 0 ]]; then
            wh_log "Currently booted from the Secondary device: ${resolved_device2}"
        else
            wh_log_local "Currently booted from the Secondary device: ${resolved_device2}"
        fi
    fi
fi

check_new_boot_devices
if [ $? -eq 0 ]; then
    wh_log "New potential migration device found."
    rm ${WH_HOME}/migration_order.sh 2>/dev/null && wh_log "Found an existing migration order that is now stale. Removing it."
    sudo $WH_PATH/wormhole.sh migrate
fi

main_loop

# Run any existing migration order
sudo $WH_PATH/wormhole.sh check-migration-plans

# Main loop
while true; do
    main_loop
    sleep $report_interval
done

sdreport_failure "Script loop unexpectedly finished."
