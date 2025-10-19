#!/bin/bash

# Configuration for rpi-eeprom BOOT_ORDER based on user specification
# 1 = SD CARD | 4 = USB-MSD | 6 = NVME | F = RESTART/LOOP
# The boot order values are read right-to-left.

BOOT_ORDER_SD="0xf41"   # SD first (1), then USB (4). This is the default.
BOOT_ORDER_USB="0xf14"  # USB first (4), then SD (1).
BOOT_ORDER_NVME="0xf146" # NVMe first (6), then USB (4), then SD (1).

function usage() {
    echo "Usage: sudo $0 <option> [device_path]"
    echo "Options:"
    echo "  -current  : Detects the current boot device (SD/USB/NVMe) and sets the boot order to prioritize it."
    echo "  -sd       : Sets priority to the SD card (BOOT_ORDER=$BOOT_ORDER_SD - SD -> USB)."
    echo "  -usb      : Sets priority to the USB device (BOOT_ORDER=$BOOT_ORDER_USB - USB -> SD)."
    echo "  -nvme     : Sets priority to the NVMe device (BOOT_ORDER=$BOOT_ORDER_NVME - NVMe -> USB)."
    echo "  -d, -device : Sets priority based on a specific block device path (e.g., /dev/sda, /dev/nvme0n1p1)."
    echo ""
    echo "The script requires sudo privileges to apply the changes."
    exit 1
}

function check_boot_order_explicitly_set() {
    local current_order
    current_order=$(rpi-eeprom-config 2>/dev/null | grep -E "^BOOT_ORDER=" | awk -F= '{print $2}' | tr -d '[:space:]')
    if [ $? -ne 0 ]; then
        echo "Error: Failed to read EEPROM configuration." >&2
        return 1
    fi
    if [ -n "$current_order" ]; then
        echo "BOOT_ORDER is explicitly set to: $current_order"
        return 0
    else
        echo "BOOT_ORDER is NOT explicitly set."
        return 1
    fi
}

function get_boot_order_from_device_path() {
    local device_path="$1"
    local base_device
    local DETECTED_ORDER=""
    base_device="$device_path"
    if [[ $device_path =~ ^/dev/nvme[0-9]+n[0-9]+p[0-9]+$ ]]; then
        base_device=$(echo "$device_path" | sed -E 's/p[0-9]+$//')
    elif [[ $device_path =~ ^/dev/sd[a-z][0-9]+$ ]]; then
        base_device=$(echo "$device_path" | sed -E 's/[0-9]+$//')
    elif [[ $device_path =~ ^/dev/mmcblk[0-9]p[0-9]+$ ]]; then
        base_device=$(echo "$device_path" | sed -E 's/p[0-9]+$//')
    fi
    if [ ! -b "$base_device" ]; then
        echo "Error: Block device '$base_device' (derived from '$device_path') does not exist or is not a block device." >&2
        return 1
    fi
    if [[ $base_device == *"/dev/mmcblk"* ]]; then
        echo "Identified '$device_path' as an SD Card device." >&2
        DETECTED_ORDER=$BOOT_ORDER_SD
    elif [[ $base_device == *"/dev/nvme"* ]]; then
        echo "Identified '$device_path' as a native NVMe device. Prioritizing NVMe (code 6)." >&2
        DETECTED_ORDER=$BOOT_ORDER_NVME
    elif [[ $base_device == *"/dev/sd"* ]]; then
        # This branch covers all USB-attached and SATA drives, which must use the USB Mass Storage Device (USB-MSD) code 4.
        echo "Identified '$device_path' as a USB-attached or SATA device. Prioritizing USB-MSD (code 4)." >&2
        DETECTED_ORDER=$BOOT_ORDER_USB
    else
        echo "Warning: Could not reliably identify device type for '$device_path'. Defaulting to SD Card priority." >&2
        DETECTED_ORDER=$BOOT_ORDER_SD
    fi
    echo "Prioritizing device type with BOOT_ORDER=$DETECTED_ORDER." >&2
    echo "$DETECTED_ORDER" # Final output, captured by command substitution
    return 0
}

function set_target_to_current() {
    local boot_device_info
    boot_device_info=$(mount | grep " / " | awk '{print $1}')
    if [ -z "$boot_device_info" ]; then
        echo "Error: Could not determine the currently mounted root device." >&2
        TARGET_ORDER=$BOOT_ORDER_SD
        echo "Defaulting to SD Card priority ($TARGET_ORDER)." >&2
        return
    fi
    echo "Determining boot order based on current root device: $boot_device_info" >&2
    TARGET_ORDER=$(get_boot_order_from_device_path "$boot_device_info")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to reliably detect the current boot device type. Defaulting to SD Card priority ($BOOT_ORDER_SD)." >&2
        TARGET_ORDER=$BOOT_ORDER_SD
    fi
}

function read_eeprom_config() {
    CURRENT_CONFIG=$(rpi-eeprom-config 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to read current EEPROM configuration with 'rpi-eeprom-config'." >&2
        exit 1
    fi
    CURRENT_ORDER=$(echo "$CURRENT_CONFIG" | grep -E "^BOOT_ORDER=" | awk -F= '{print $2}' | tr -d '[:space:]')
}

function apply_config() {
    local temp_config_file="$1"
    local new_order="$2"
    echo "Attempting to change BOOT_ORDER to: $new_order"
    if [[ "$CURRENT_ORDER" = "$new_order" ]] || \
       ( [ -z "$CURRENT_ORDER" ] && [ "$new_order" = "$BOOT_ORDER_SD" ] ); then
        echo "The current BOOT_ORDER is already set to $new_order (or the default). No change required."
        return 0
    fi
    echo "$CURRENT_CONFIG" > "$temp_config_file"
    if [ -n "$CURRENT_ORDER" ]; then
        sed -i.bak "s/^BOOT_ORDER=.*/BOOT_ORDER=$new_order/" "$temp_config_file"
        rm -f "${temp_config_file}.bak"
        echo "Existing BOOT_ORDER=$CURRENT_ORDER was found and replaced."
    else
        echo "BOOT_ORDER=$new_order" >> "$temp_config_file"
        echo "BOOT_ORDER was not found and will be added."
    fi
    echo "Applying new configuration from $temp_config_file."
    echo "This schedules the EEPROM update for the next reboot."
    
    rpi-eeprom-config --apply "$temp_config_file"
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Boot order set to $new_order. Reboot to apply."
        return 0
    else
        echo "ERROR: Failed to apply EEPROM configuration." >&2
        return 1
    fi
}

if [ $# -eq 0 ]; then
    usage
fi

if [ "$1" = "-check" ]; then
    check_boot_order_explicitly_set
    exit $?
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo) for configuration changes." >&2
    usage
fi

case "$1" in
    -sd)
        TARGET_ORDER=$BOOT_ORDER_SD
        echo "Requested: SD Card priority ($TARGET_ORDER)."
        ;;
    -usb)
        TARGET_ORDER=$BOOT_ORDER_USB
        echo "Requested: USB priority ($TARGET_ORDER)."
        ;;
    -nvme)
        TARGET_ORDER=$BOOT_ORDER_NVME
        echo "Requested: NVMe priority ($TARGET_ORDER)."
        ;;
    -current)
        set_target_to_current
        ;;
    -d|-device)
        if [ -z "$2" ]; then
            echo "Error: The '$1' option requires a device path argument (e.g., /dev/sda)." >&2
            usage
        fi
        DEVICE_PATH="$2"
        echo "Requested device path: $DEVICE_PATH."
        DETERMINED_ORDER=$(get_boot_order_from_device_path "$DEVICE_PATH")
        if [ $? -ne 0 ]; then
             echo "Fatal Error: Cannot proceed because the device path could not be resolved." >&2
             exit 1
        fi
        TARGET_ORDER="$DETERMINED_ORDER"
        ;;
    *)
        echo "Error: Invalid option '$1'." >&2
        usage
        ;;
esac

read_eeprom_config

TEMP_CONF=$(mktemp)
trap "rm -f $TEMP_CONF" EXIT INT TERM

apply_config "$TEMP_CONF" "$TARGET_ORDER"
exit $?
