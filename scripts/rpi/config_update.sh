#!/bin/bash
#
# Usage: sudo ./config_update.sh <variable_name> <new_value>
# Example: sudo ./config_update.sh ip 192.168.1.50

ENV_FILE="/etc/environment"
VARIABLE_KEY=""
INPUT_NAME="$1"
NEW_VALUE="$2"

display_usage() {
    echo -e "Usage: $0 <variable_name> <new_value>"
    echo "Available variable names:"
    echo "  ip             -> WH_IP_ADDR (Valid IPv4, must match current system IP)"
    echo "  crypto         -> WH_CRYPTO_KEY (Non-empty string)"
    echo "  apikey         -> WH_HARDWARE_API_KEY (Non-empty alphanumeric/hex)"
    echo "  url            -> WH_SERVER_API_URL (Valid HTTP/HTTPS URL)"
    echo "  path           -> WH_PATH (Absolute path starting with /)"
    echo "  home           -> WH_HOME (Path starting with /home/)"
    echo "  domain         -> WH_DOMAIN (Valid HTTPS URL)"
    echo "  wgport         -> WH_WIREGUARD_PORT (Port number 1-65535)"
    echo "  boot-primary   -> WH_BOOT_DEVICE ('USB', 'SDCARD', 'NVME', or /dev/path)"
    echo "  boot-secondary -> WH_BOOT_DEVICE2"
    exit 1
}

if [[ $EUID -ne 0 ]]; then
   echo -e "Error: This script must be run as root (using 'sudo') to edit $ENV_FILE."
   exit 1
fi

if [ "$#" -ne 2 ]; then
    display_usage
fi

validate_ipv4() {
    if ! [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "Validation Error: '$1' is not a valid IPv4 address format (e.g., 192.168.1.1)."
        return 1
    fi
    my_ip=$(nmcli -t -f IP4.ADDRESS device show | head -1 | cut -d"/" -f1 | cut -d : -f2)
    if [ -z "$my_ip" ]; then
        echo -e "Warning: Could not determine current system IP. Skipping IP match check."
    elif [ "$1" != "$my_ip" ]; then
        echo -e "Validation Error: The new IP value ('$1') does not match the current actual system IP ('$my_ip')."
        return 1
    else
        echo -e "Info: IP match check passed. Current system IP is $my_ip."
    fi
    return 0
}

validate_url() {
    # Must start with http(s):// and contain a domain/host part
    if [[ $1 =~ ^https?://[a-zA-Z0-9\.\-]+(\.[a-zA-Z]{2,})?(\/.*)?$ ]]; then
        return 0
    else
        echo -e "Validation Error: '$1' is not a valid URL (must start with http:// or https:// and contain a host)."
        return 1
    fi
}

validate_port() {
    # Must be an integer between 1 and 65535
    if [[ $1 =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; then
        return 0
    else
        echo -e "Validation Error: '$1' is not a valid port number (1-65535)."
        return 1
    fi
}

validate_path_abs() {
    # Must be an absolute path (starts with /)
    if [[ $1 =~ ^/.*$ ]]; then
        return 0
    else
        echo -e "Validation Error: '$1' is not a valid absolute path (must start with /)."
        return 1
    fi
}

validate_path_home() {
    # Must start with /home/
    if [[ $1 =~ ^/home/.*$ ]]; then
        return 0
    else
        echo -e "Validation Error: '$1' is not a valid home path (must start with /home/). The value you provided is: $1"
        return 1
    fi
}

validate_non_empty_hex() {
    # Non-empty and checks for standard alphanumeric/hex characters
    if [[ -z "$1" ]]; then
        echo -e "Validation Error: API Key value cannot be empty."
        return 1
    fi
    if [[ $1 =~ ^[a-fA-F0-9]+$ ]]; then
        return 0
    else
        echo -e "Validation Error: '$1' must be a non-empty alphanumeric/hexadecimal string."
        return 1
    fi
}

validate_non_empty_simple() {
    # Just ensure the string is not empty
    if [[ -z "$1" ]]; then
        echo -e "Validation Error: Crypto Key value cannot be empty."
        return 1
    fi
    return 0
}

validate_boot_device() {
    local value="$1"
    local accepted_values=("USB" "SDCARD" "NVME")
    local is_accepted=0
    for accepted in "${accepted_values[@]}"; do
        if [[ "$value" == "$accepted" ]]; then
            is_accepted=1
            break
        fi
    done
    if [ "$is_accepted" -eq 1 ]; then
        echo "Info: Boot device '$value' is a recognized pre-set string."
        return 0
    fi
    if [[ $value =~ ^/dev/[a-z]+[0-9]?$ ]]; then
        if [ -b "$value" ]; then
            echo "Info: Boot device '$value' is a valid, existing block device path."
            return 0
        else
            echo -e "Validation Error: '$value' looks like a device path but does not correspond to an existing block device (e.g., /dev/sda)."
            return 1
        fi
    fi
    echo -e "Validation Error: '$value' must be a case-sensitive pre-set string (${accepted_values[*]}) or a path to a valid block device (e.g., /dev/sda)."
    return 1
}

case "$INPUT_NAME" in
    ip)
        VARIABLE_KEY="WH_IP_ADDR"
        validate_ipv4 "$NEW_VALUE" || exit 1
        ;;
    crypto)
        VARIABLE_KEY="WH_CRYPTO_KEY"
        validate_non_empty_simple "$NEW_VALUE" || exit 1
        ;;
    apikey)
        VARIABLE_KEY="WH_HARDWARE_API_KEY"
        validate_non_empty_hex "$NEW_VALUE" || exit 1
        ;;
    url)
        VARIABLE_KEY="WH_SERVER_API_URL"
        validate_url "$NEW_VALUE" || exit 1
        ;;
    path)
        VARIABLE_KEY="WH_PATH"
        validate_path_abs "$NEW_VALUE" || exit 1
        ;;
    home)
        VARIABLE_KEY="WH_HOME"
        validate_path_home "$NEW_VALUE" || exit 1
        ;;
    domain)
        VARIABLE_KEY="WH_DOMAIN"
        validate_url "$NEW_VALUE" || exit 1
        ;;
    wgport)
        VARIABLE_KEY="WH_WIREGUARD_PORT"
        validate_port "$NEW_VALUE" || exit 1
        ;;
    boot-primary)
        VARIABLE_KEY="WH_BOOT_DEVICE"
        validate_boot_device "$NEW_VALUE" || exit 1
        ;;
    boot-secondary)
        VARIABLE_KEY="WH_BOOT_DEVICE2"
        validate_boot_device "$NEW_VALUE" || exit 1
        ;;
    *)
        echo -e "Error: Unknown variable name '$INPUT_NAME'."
        display_usage
        ;;
esac

OLD_VALUE=$(grep -oP "^${VARIABLE_KEY}=\"\K.*?(?=\")" "$ENV_FILE")
if ! grep -q "^${VARIABLE_KEY}=\".*\"" "$ENV_FILE"; then
    echo -e "Error: The variable '$VARIABLE_KEY' was not found in '$ENV_FILE'."
    echo "Please ensure it is present in the format: ${VARIABLE_KEY}=\"old_value\""
    exit 1
fi

echo -e "Updating $VARIABLE_KEY in $ENV_FILE to \"$NEW_VALUE\"..."
sed -i.bak "s|^${VARIABLE_KEY}=\".*\"|${VARIABLE_KEY}=\"$NEW_VALUE\"|" "$ENV_FILE"
if [ $? -eq 0 ]; then
    echo -e "Success: $VARIABLE_KEY has been updated from '$OLD_VALUE' to '$NEW_VALUE'."
    echo "A backup of the original file was created at ${ENV_FILE}.bak"
    source "$ENV_FILE"
else
    echo -e "Error: Failed to update the file using sed."
    exit 1
fi

echo "Reboot to apply configuration"
exit 0
