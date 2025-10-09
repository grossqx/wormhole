#!/bin/bash

report_interval=60

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


# Files to be sourced
dependencies=(
    "/etc/environment"
    "/etc/profile.d/rpi_sysinfo.sh"
    "/etc/profile.d/wh_logger.sh"
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
)

# Required functions
required_functions=(
    "rpi-sysinfo"
    "wh_log_local"
    "wh_log_remote"
    "wh_log"
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
    echo -e "Start state indicates a successfull firstrun.sh exection"
    sdreport_ready "Started"
fi

# Main loop
while true; do
    # Send telemetry to the server
    wh_send_payload "$(rpi-sysinfo --json)" "${WH_SERVER_API_URL}/wh/telemetry"
    sleep $report_interval
done

sdreport_failure "Script loop unexpectedly finished."
