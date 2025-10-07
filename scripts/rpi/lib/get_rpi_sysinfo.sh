#!/bin/bash

#####################################################################################
# SCRIPT: Raspberry Pi System Information Function
#
# DESCRIPTION:
# This script defines a shell function named `get_rpi_sysinfo` that collects
# various system and hardware metrics from a Raspberry Pi, including hardware
# details, temperature readings, bootloader status, and Docker information.
#
# The function supports two output modes:
# 1. Human-readable text output (default): Provides a clear, formatted list
#    of all sensor values for easy viewing in a terminal.
# 2. JSON payload output (--json): Formats all collected data as a
#    machine-parsable JSON object, which is useful for integrations with other
#    systems like monitoring dashboards or APIs.
#
# USAGE:
# To use this function, place this script in `/etc/profile.d/`.
#
# To get a human-readable output:
#   get_rpi_sysinfo
#
# To get a JSON output:
#   get_rpi_sysinfo --json
#
# DEPENDENCIES:
# - vcgencmd: Standard Raspberry Pi command-line utility.
# - rpi-eeprom-update: Utility for checking bootloader and EEPROM status.
# - docker (optional): The script will detect if Docker is installed.
# - jq (for JSON output): A lightweight and flexible command-line JSON processor.
#   It is highly recommended for creating valid JSON payloads from shell scripts.
#   You can install it using: sudo apt-get install jq
#
#####################################################################################
#
# NOTE:
#   Monitoring voltage so far only possible on Raspberry Pi 5:
#   It is essential to keep the supply voltage above 4.8V for reliable performance. 
#   Note that the voltage from some USB chargers/power supplies can fall as low as 4.2V. 
#   This is because they are usually designed to charge a 3.7V LiPo battery, 
#   not to supply 5V to a computer. To monitor the Raspberry Pi’s PSU voltage, 
#   you will need to use a multimeter to measure between the VCC and GND pins on the GPIO. 
#   More information is available in the power section of the documentation.
#   If the voltage drops below 4.63V (±5%), the ARM cores and the GPU will be throttled 
#   back, and a message indicating the low voltage state will be added to the kernel log.
#   The Raspberry Pi 5 PMIC has built in ADCs that allow the supply voltage to be measured. 
#   To view the current supply voltage, run the following command:
#   vcgencmd pmic_read_adc EXT5V_V
#
#####################################################################################

get_rpi_sysinfo() {
    # Determine if JSON output is requested
    local json_output=false
    if [[ "$1" == "--json" ]]; then
        json_output=true
    fi

    # Check for dependencies
    if "$json_output" && ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is required for JSON output but is not installed. Please install it." >&2
        return 1
    fi

    # EEPROM update sensor
    local eeprom_update
    eeprom_update=$(rpi-eeprom-update)
    local RPI_UPDATE_EEPROM=false
    if echo "$eeprom_update" | grep -q "UPDATE AVAILABLE"; then
        RPI_UPDATE_EEPROM=true
    fi

    local RPI_BOOTLOADER_VERSION=$(echo "$eeprom_update" | grep 'CURRENT' | head -n 1 | sed 's/^[[:space:]]*CURRENT:[[:space:]]*//')
    local RPI_BOOTLOADER_RELEASE=$(echo "$eeprom_update" | grep 'RELEASE' | sed 's/^[[:space:]]*RELEASE:[[:space:]]*//')
    local RPI_BOOTLOADER_VL805=$(echo "$eeprom_update" | grep -A 2 'VL805_FW' | grep 'CURRENT' | awk '{print $NF}')

    # get_throttled bit by bit
    local throttled_hex=$(vcgencmd get_throttled | cut -d '=' -f 2)
    local throttled_dec=$((throttled_hex))
    local throttled_status_message=""
    if [ "$throttled_dec" -eq 0 ]; then
        throttled_status_message+="Everything is running normally"
    fi
    if (( throttled_dec & 0x1 )); then
        throttled_status_message+="Under-voltage detected. "
    fi
    if (( throttled_dec & 0x2 )); then
        throttled_status_message+="Frequency capped. "
    fi
    if (( throttled_dec & 0x4 )); then
        throttled_status_message+="Currently throttled. "
    fi
    if (( throttled_dec & 0x8 )); then
        throttled_status_message+="Soft temperature limit active. "
    fi
    if (( throttled_dec & 0x10000 )); then
        throttled_status_message+="Under-voltage has occurred. "
    fi
    if (( throttled_dec & 0x20000 )); then
        throttled_status_message+="Frequency capping has occurred. "
    fi
    if (( throttled_dec & 0x40000 )); then
        throttled_status_message+="Throttling has occurred. "
    fi
    if (( throttled_dec & 0x80000 )); then
        throttled_status_message+="Soft temperature limit has occurred. "
    fi
    local RPI_THROTTLED_STATUS=$throttled_status_message

    # Hardware information
    local RPI_MODEL=$(grep "Model" "/proc/cpuinfo" | awk -F': ' '{print $2}')
    local RPI_SERIAL_NUMBER=$(grep "Serial" "/proc/cpuinfo" | awk '{print $NF}')
    local RPI_BOARD_REVISION=$(grep "Revision" "/proc/cpuinfo" | awk '{print $NF}')
    local RPI_TEMPERATURE_CPU=$(cat /sys/class/thermal/thermal_zone0/temp | awk '{printf "%.1f\n", $1/1000}')
    local RPI_TEMPERATURE_GPU=$(vcgencmd measure_temp | cut -d '=' -f 2 | cut -d "'" -f 1)

    # Docker sensors
    local RPI_DOCKER_VERSION="not_installed"
    local RPI_DOCKER_BUILD="not_installed"
    if command -v docker &> /dev/null; then
        local docker_version
        docker_version=$(docker --version)
        RPI_DOCKER_VERSION=$(echo "$docker_version" | awk '{print $3}' | tr -d ',')
        RPI_DOCKER_BUILD=$(echo "$docker_version" | awk '{print $5}')
    fi

    if "$json_output"; then
        timestamp=$(date +%s%3N)
        jq -n \
            --argjson timestamp $timestamp \
            --arg model "$RPI_MODEL" \
            --arg serial "$RPI_SERIAL_NUMBER" \
            --arg revision "$RPI_BOARD_REVISION" \
            --argjson eeprom_update_available "$RPI_UPDATE_EEPROM" \
            --arg bootloader_version "$RPI_BOOTLOADER_VERSION" \
            --arg bootloader_release "$RPI_BOOTLOADER_RELEASE" \
            --arg bootloader_vl805 "$RPI_BOOTLOADER_VL805" \
            --arg cpu_temp "$RPI_TEMPERATURE_CPU" \
            --arg gpu_temp "$RPI_TEMPERATURE_GPU" \
            --arg throttled_status "$RPI_THROTTLED_STATUS" \
            --arg docker_version "$RPI_DOCKER_VERSION" \
            --arg docker_build "$RPI_DOCKER_BUILD" \
            '{
                "timestamp": $timestamp,
                "hardware": {
                    "model": $model,
                    "serial_number": $serial,
                    "board_revision": $revision
                },
                "firmware": {
                    "eeprom_update_available": $eeprom_update_available,
                    "bootloader_version": $bootloader_version,
                    "bootloader_release": $bootloader_release,
                    "bootloader_vl805": $bootloader_vl805
                },
                "sensors": {
                    "cpu_temperature": $cpu_temp,
                    "gpu_temperature": $gpu_temp,
                    "throttled_status": $throttled_status
                },
                "software": {
                    "docker_version": $docker_version,
                    "docker_build": $docker_build
                }
            }'
    else
        echo "Model: ${RPI_MODEL}"
        echo "Serial Number: ${RPI_SERIAL_NUMBER}"
        echo "Board Revision: ${RPI_BOARD_REVISION}"
        echo "EEPROM update available: ${RPI_UPDATE_EEPROM}"
        echo "Bootloader version: ${RPI_BOOTLOADER_VERSION}"
        echo "Bootloader release: ${RPI_BOOTLOADER_RELEASE}"
        echo "Bootloader VL805: ${RPI_BOOTLOADER_VL805}"
        echo "CPU Temperature: ${RPI_TEMPERATURE_CPU}°C"
        echo "GPU Temperature: ${RPI_TEMPERATURE_GPU}°C"
        echo "Throttled status: ${RPI_THROTTLED_STATUS}"
        echo "Docker version: ${RPI_DOCKER_VERSION}"
        echo "Docker build: ${RPI_DOCKER_BUILD}"
    fi
}