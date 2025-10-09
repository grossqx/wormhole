#!/bin/bash

url=$1
api_key=$2
CONFIG_PATH=$3

# Decryption settings
DECRYPTION_KEY="seed"
CIPHER="-aes-256-cbc"
KEY_DERIVATION="-pbkdf2"

## Text colors:
source ${base_dir}/res/theme.env

# Define the list of required variables
required_variables=(
    "hostname"
    "device_tag"
    "search"
    "safety_timeout"
    "timezone"
    "ip_addr"
    "domain"
    "wh_port"
    "wifi_ssid"
    "ssh_user"
)

# Init empry list of missing variables
missing_variables=()

function check_missing_variables() {
    # Add all required variables
    for variable in "${required_variables[@]}"; do
        # Use indirect expansion to check the value of the variable
        if [[ "${!variable}" == "null" || -z "${!variable}" ]]; then
            missing_variables+=("$variable")
        fi
    done
    # Check for missing wifi variables if wifi_ssid is not null or empty
    if [[ ! -z "${wifi_ssid}" && "${wifi_ssid}" != "null" ]]; then
        if [[ -z "${wifi_password}" ]]; then
            missing_variables+=("wifi_password")
        fi
        if [[ -z "${wifi_loc}" ]]; then
            missing_variables+=("wifi_loc")
        fi
    fi
    # Check for missing ssh variables if ssh_user is set
    if [[ ! -z "${ssh_user}" && "${ssh_user}" != "null" ]]; then
        if [[ -z "${ssh_password}" ]]; then
            missing_variables+=("ssh_password")
        fi
        if [[ -z "${ssh_port}" ]]; then
            missing_variables+=("ssh_port")
        fi
    fi
    return "${#missing_variables[@]}"
}

function decrypt_password() {
    local encrypted_password=$1
    local context=$2
    local decrypted_password=""
    echo "Decrypting ${context} password..." >&2
    decrypted_password=$(echo "$encrypted_password" | base64 --decode | openssl enc "${CIPHER}" "${KEY_DERIVATION}" -d -salt -pass pass:"${DECRYPTION_KEY}" 2>/dev/null | tail -n 1)
    if [[ -z "$decrypted_password" ]]; then
        errors=true
        echo -e "${T_YELLOW}${context} password decryption failed:" >&2
        echo -e "$encrypted_password" | base64 --decode | openssl enc "${CIPHER}" "${KEY_DERIVATION}" -d -salt -pass pass:"${DECRYPTION_KEY}" >&2
        echo -e "${T_NC}" >&2
        return 1
    else
        echo -e "${T_GREEN}${context} password decryption successful!${T_NC}" >&2
    fi
    echo "$decrypted_password"
    return 0
}

# Request the configuration from the server's API and prepare the data
echo "Requesting configuration from the server..."
send_report "Requesting configuration from the server"
response=$(curl -s -w "\n%{http_code}" -X GET ${url} -H "Authorization: Bearer ${api_key}")
http_code=$(echo "$response" | tail -n1) # Extract the last line for the status code
json_data=$(echo "$response" | sed '$d') # Remove the last line to get the JSON data
if [[ "$http_code" == "200" ]]; then
   echo "Success!"
else
   echo
   echo "${T_RED}Error: ${http_code} - Response body: ${json_data}${T_NC}"
   exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "Error: jq not installed."
    exit 1
fi
config_keys=$(echo "$json_data" | jq -r 'keys[]') # The '-r' flag outputs raw without quotes.
IFS=$'\n' # Change Internal Field Separator to newline to correctly handle multi-line output
config_array=($config_keys)

# Initialize configuration menu variables
selected_index=-1
choice=""

# Display configuration picker menu
if [ "${#config_array[@]}" -eq 1 ]; then
    echo
    echo "Single configuration found for this user"
    selected_index=0
else
    echo
    echo "Configurations available on the server:"
    printf "%-3s %-30s %-15s %-1s\n" "#" "NAME" "TAG" "SEARCH QUERY"
    echo "=================================================================="
    for i in "${!config_array[@]}"; do
        key="${config_array[$i]}"
        # Use jq to get the description for the current key.
        description=$(echo "$json_data" | jq -r --arg key "$key" '.[$key]."description"')
        devicetag=$(echo "$json_data" | jq -r --arg key "$key" '.[$key]."device-tag"')
        search=$(echo "$json_data" | jq -r --arg key "$key" '.[$key]."search"')
        printf "%-3d ${T_BOLD}${T_BLUE}%-30s${T_NC} ${T_GREEN}%-15s${T_NC} %-1s\n" $((i+1)) ${key} ${devicetag} ${search}
        printf "%-3s ${T_ITALIC}%-30s${T_NC}\n" " " ${description}
    done
    echo
    while true; do # This loop will continue to prompt the user until a valid option is selected.
        read -p "Enter your choice: " choice
        # Check if the input is a valid number.
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo "Error: Invalid input. Please enter a number."
            continue
        fi
        # Check if the number is within the valid range.
        selected_index=$((choice-1))
        if [[ "$selected_index" -ge 0 && "$selected_index" -lt "${#config_array[@]}" ]]; then
            break # Exit the loop because a valid choice was made
        else
            echo "Error: Invalid choice. Please select a number from the menu."
        fi
    done
fi

errors=false

# Get the selected configuration key from the array
config="${config_array[$selected_index]}"
send_report "User selected configuration ${config}"

# Use jq to extract the details of the selected configuration and assign to variables
hostname=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."hostname"')
description=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."description"')
device_tag=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."device-tag"')
search=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."search"')
safety_timeout=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."safety-timeout"')
timezone=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."timezone"')
ip_addr=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."ip-addr"')
domain=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."domain"')
wh_port=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."wh-port"')
boot_device=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."boot-device"')
boot_device2=$(echo "$json_data" | jq -r --arg key "$config" '.[$key]."boot-device2"')

# Handle Wifi Configuration
wifi_data=$(echo "$json_data" | jq -r --arg key "$config" '.[$key].wifi')
if [[ "$wifi_data" != "null" ]]; then
    wifi_encrypted=$(echo "$wifi_data" | jq -r '.encrypted')
    wifi_ssid=$(echo "$wifi_data" | jq -r '.ssid')
    wifi_password=$(echo "$wifi_data" | jq -r '.password')
    wifi_loc=$(echo "$wifi_data" | jq -r '.loc')
    if [[ "$wifi_encrypted" == "true" ]]; then
        wifi_password=$(decrypt_password "$wifi_password" "WiFi")
        if [[ $? -eq 1 ]]; then
            errors=true
        fi
    fi
else
    wifi_encrypted=""
    wifi_ssid=""
    wifi_password=""
    wifi_loc=""
fi

# Handle SSH Configuration
ssh_data=$(echo "$json_data" | jq -r --arg key "$config" '.[$key].ssh')
if [[ "$ssh_data" != "null" ]]; then
    ssh_encrypted=$(echo "$ssh_data" | jq -r '.encrypted')
    ssh_user=$(echo "$ssh_data" | jq -r '.user')
    ssh_password=$(echo "$ssh_data" | jq -r '.password')
    ssh_port=$(echo "$ssh_data" | jq -r '.port')
    if [[ "$ssh_encrypted" == "true" ]]; then
        ssh_password=$(decrypt_password "$ssh_password" "SSH")
        if [[ $? -eq 1 ]]; then
            errors=true
        fi
    fi
else
    ssh_encrypted=""
    ssh_user=""
    ssh_password=""
    ssh_port=""
fi

# Special case to fill in the configuration name if the template name is 'empty'
if [[ $config == "empty" ]]; then
    missing_variables+=("config")
fi

# Check for missing required variables
check_missing_variables
missing_count=$?
echo -e "${T_BLUE}Missing variables: ${missing_count}${T_NC}"
if [[ ${missing_count} -gt 0 ]]; then
    for missing_variable in "${missing_variables[@]}"; do
        read -p "   Enter value for $missing_variable: " missing_value
        eval "$missing_variable=\"$missing_value\""
    done
fi

## Reset to check again for WiFi and ssh credentials
missing_variables=()
check_missing_variables
missing_count=$?
if [[ ${missing_count} -gt 0 ]]; then
    for missing_variable in "${missing_variables[@]}"; do
        read -p "   Enter value for $missing_variable: " missing_value
        eval "$missing_variable=\"$missing_value\""
    done
fi

send_report "Saving configuration to file"

rm -f ${CONFIG_PATH}
echo "RPI_CONFIG_NAME='${config}'" >> ${CONFIG_PATH}
echo "RPI_HOSTNAME='${hostname}'" >> ${CONFIG_PATH}
echo "RPI_DESCRIPTION='${description}'" >> ${CONFIG_PATH}
echo "RPI_CONFIG_TAG='${device_tag}'" >> ${CONFIG_PATH}
echo "RPI_CONFIG_SEARCH='${search}'" >> ${CONFIG_PATH}
echo "RPI_CONFIG_TIMEOUT='${safety_timeout}'" >> ${CONFIG_PATH}
echo "RPI_TIMEZONE='${timezone}'" >> ${CONFIG_PATH}
echo "RPI_IP_ADDR='${ip_addr}'" >> ${CONFIG_PATH}
echo "RPI_DOMAIN='${domain}'" >> ${CONFIG_PATH}
echo "RPI_WH_PORT='${wh_port}'" >> ${CONFIG_PATH}
echo "RPI_HARDWARE_API_KEY=$(openssl rand -hex 16)" >> ${CONFIG_PATH}
echo "RPI_BOOT_DEVICE='${boot_device}'" >> ${CONFIG_PATH}
echo "RPI_BOOT_DEVICE2='${boot_device2}'" >> ${CONFIG_PATH}
# WiFi
echo "RPI_WIFI_ENCRYPTED='${wifi_encrypted}'" >> ${CONFIG_PATH}
echo "RPI_WIFI_SSID='${wifi_ssid}'" >> ${CONFIG_PATH}
echo "RPI_WIFI_PASSWORD='${wifi_password}'" >> ${CONFIG_PATH}
echo "RPI_WIFI_LOC='${wifi_loc}'" >> ${CONFIG_PATH}
# SSH
echo "RPI_SSH_ENCRYPTED='${ssh_encrypted}'" >> ${CONFIG_PATH}
echo "RPI_SSH_USER='${ssh_user}'" >> ${CONFIG_PATH}
echo "RPI_SSH_PASSWORD='${ssh_password}'" >> ${CONFIG_PATH}
echo "RPI_SSH_PORT='${ssh_port}'" >> ${CONFIG_PATH}

# Conclude
if [[ $errors == true ]]; then
    exit 1
else
    exit 0
fi