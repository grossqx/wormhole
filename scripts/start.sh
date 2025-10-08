#!/bin/bash

source ~/.bashrc

# Resolve parent directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
base_dir="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# Script info
binary_name="wormhole-installer"
app_name="Wormhole image installer"

# Endpoints for specific API requests
endpoint_install="/wh/install"
endpoint_health="/wh/health"
endpoint_get_username="/wh/get_username"
endpoint_get_pollrate="/wh/get_pollrate"
endpoint_get_config="/wh/get_config"
endpoint_upload_config="/wh/upload_config"
endpoint_report_install="/wh/install_log_write"
endpoint_read_install="/wh/install_log_read"

# Files and directories
persistent_data_dir="$HOME/.config/wormhole"
config_memos_dir="$HOME/wormhole"
checkpoint_file="${persistent_data_dir}/.checkpoint"
install_device_file="${persistent_data_dir}/.installdevice"
install_id_file="${persistent_data_dir}/.installid"
configuration_file="${persistent_data_dir}/config.env"
firstrun_file="${persistent_data_dir}/firstrun.sh"
firstrun_template_file="${base_dir}/rpi/firstrun_template.sh"
symlink_path="/usr/local/bin/${binary_name}"

## DEBUG
SKIP_DEPENDENCIES=false
PROCEED_WITHOUT_LOGGING=false

# Set default values for all options. These will be overwritten by command-line options.
option_install_media=""

## Text colors:
source ${base_dir}/res/theme.env
source ${base_dir}/res/settings.sh

# FUNCTIONS
function print_header(){
    echo -e "🕳  ${T_BOLD}======= Wormhole - install v${script_version} =======${T_NC} / ${T_GREEN}${install_id}${T_NC}"
}

# Output the progress bar with percentage.
function print_progressbar() {
    local progress="$1"
    local progress_bar_length="$2"
    local message="$3"
    local num_stages="$4"
    local filled_chars=$(echo "(${progress} * ${progress_bar_length}) / 100" | bc)
    local remaining_chars=$((progress_bar_length - filled_chars))
    local base_filled=$(printf '%*s' "$filled_chars" | tr ' ' '=')
    local base_empty=$(printf '%*s' "$remaining_chars" | tr ' ' '.')
    local final_bar=""
    if [[ -n "$num_stages" ]] && [[ "$num_stages" -gt 1 ]]; then
        local stage_length
        stage_length=$(echo "${progress_bar_length} / ${num_stages}" | bc)
        local current_filled_index=0
        local current_empty_index=0
        for ((i = 1; i <= num_stages; i++)); do
            local segment_filled_chars=$((filled_chars - current_filled_index))
            if [[ "$segment_filled_chars" -gt "$stage_length" ]]; then
                segment_filled_chars="$stage_length"
            elif [[ "$segment_filled_chars" -lt 0 ]]; then
                segment_filled_chars=0
            fi
            local segment_empty_chars=$((stage_length - segment_filled_chars))
            local segment_filled="${base_filled:$current_filled_index:$segment_filled_chars}"
            local segment_empty="${base_empty:$current_empty_index:$segment_empty_chars}"
            final_bar="${final_bar}${segment_filled}${segment_empty}" # Append to the final bar
            if [[ "$i" -lt "$num_stages" ]]; then # Append the separator if it's not the last stage
                final_bar="${final_bar}|"
            fi
            # Update the starting indices for the next segment
            current_filled_index=$((current_filled_index + segment_filled_chars))
            current_empty_index=$((current_empty_index + segment_empty_chars))
        done
    else
        final_bar="${base_filled}${base_empty}"
    fi
    printf "\033[K  ${T_GREEN}%s${T_NC} ${T_BOLD}%s${T_NC} ${T_BLUE}%s${T_NC}\n" "[${final_bar}]" "${progress}%" "${message}"
}

function run_status_checks() {
    problem=0
    print_header

    ## Display options if provided by the user
    if [[ ! -z "$option_install_media" ]]; then
        echo "Install media:     '${option_install_media}'"
    fi
    ## List checkpoints
    if [ "$INTERNET_OK" == true ]; then
        echo -e "✅ Internet connection\t\t${T_GREEN}active${T_NC}"
    else
        echo -e "❌ No internet connection"
        problem=1
    fi
    
    if [[ ! -z "$api_key" ]]; then
        echo -e "✅ API key provided. \t\tuser: ${T_BLUE}${install_user}${T_NC}"
    else
        echo -e "❌ No API key provided"
        problem=2
    fi
    
    if [[ "$API_SERVER_STATUS" == "healthy" ]]; then
        echo -e "✅ API host online\t\t${api_domain} ${T_GREEN}(${API_SERVER_STATUS})${T_NC}"
        API_HOST_OK=true
    else
        echo -e "❌ API host offline\t\t${api_domain} ${T_RED}(${API_SERVER_STATUS})${T_NC}"
        problem=3
    fi

    if [[ "$DEPENDENCIES_CHECKED" == true ]]; then
        echo -e "✅ Local dependencies\t\t${T_GREEN}Done${T_NC}"
    else
        echo -e "❌ Local dependencies not installed."
        problem=4
    fi

    if [[ "$CONFIG_READY" == true ]]; then
        echo -e "✅ Configuration ready\t\t${configuration_file}"
        problem=6
    else
        echo -e "❌ No configuration " 
        problem=5
    fi

    if [[ ! -z "$INSTALL_DEVICE" ]]; then
        echo -e "✅ Install media\t\t${INSTALL_DEVICE}" 
        problem=7
    else
        echo -e "❌ No install media picked" 
        problem=6
    fi

    if [[ "$FIRSTRUN_READY" == true ]]; then
        echo -e "✅ firstrun.sh ready\t\t${firstrun_file}"
        problem=8
    else
        echo -e "❌ No firstrun.sh" 
        problem=7
    fi

    if [[ "$IMAGE_WRITTEN" == true ]]; then
        echo -e "✅ Image written\t\t${T_GREEN}Done${T_NC}"
        problem=9
    else
        echo -e "❌ Image not yet written" 
        problem=8
    fi

    if [[ "$DEVICE_REACHABLE" == true ]]; then
        echo -e "✅ RPi online\t\t ${online_ip}"
        problem=10
    else
        echo -e "❌ RPi not yet online" 
        problem=9
    fi

    if [[ "$ROUTER_CONFIGURED" == true ]]; then
        echo -e "✅ Router configured\t\t${T_GREEN}Done${T_NC} ${ROUTER_CONFIG_INSTRUCTION_FILE}"
        problem=12
    else
        echo -e "❌ Router not configured\t\t${ROUTER_CONFIG_INSTRUCTION_FILE}" 
        problem=10
    fi

    if [[ "$CONFIG_UPLOADED" == true ]]; then
        echo -e "✅ Configuration uploaded\t${RPI_CONFIG_NAME} - ${install_id}"
        problem=13
    else
        echo -e "❌ Server waiting for configuration" 
        problem=12
    fi

    if [[ "$AUTOINSTALL_DONE" == true ]]; then
        echo -e "✅ Wormhole on RPi\t\t${T_GREEN}Done${T_NC}"
        problem=14
    else
        echo -e "❌ Wormhole install on RPi" 
        problem=13
    fi
    echo
    return "$problem"
}

## Fails the script if current progress checkpoint is less than expected
function expect_progress {
    local expected_progress=$1
    run_status_checks
    local status_code=$?
    if (( status_code > expected_progress-1 )); then
        :
    else
        echo "Error: main script step failed: "
        echo "status code ${status_code}, expected ${expected_progress}"
        exit 1
    fi
}

# Function to display the help message.
function show_help() {
    cat << EOF
Usage: ${binary_name} <URL> <TOKEN> [options]

A template script to demonstrate option and argument parsing.

Arguments:
  URL                 The API domain to use (e.g., api.domain.com).
  TOKEN               The API key to be read from the environment.

Options:
  --lang=<language>   Specify a language code. "en" or "ua".
  --search=<query>    Specify a search query in quotes (e.g., "OS Lite").
  --device=<path>     Specify a device path (e.g., "/dev/mmcblk0").
  --help              Display this help message and exit.
EOF
}

# A function to prompt the user for confirmation.
#
# Arguments:
#   -y: Sets 'yes' as the default answer.
#   -n: Sets 'no' as the default answer.
#   -e: Expects no input; just for the user to press Enter to continue.
#   A custom message string (optional).
#
# Returns:
#   0 on 'yes' or 'enter' (for -e option), non-zero on 'no'.
function get_user_input() {
    local default_yes=false
    local default_no=false
    local expect_enter=false
    local no_report=false
    local custom_message=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y)
                default_yes=true
                ;;
            -n)
                default_no=true
                ;;
            -e)
                expect_enter=true
                ;;
            -l)
                no_report=true
                ;;
            *)
                custom_message="$1"
                ;;
        esac
        shift
    done
    local prompt_message=""
    local prompt_options=""
    if [[ "$expect_enter" == true ]]; then
        if [[ -z "$custom_message" ]]; then
            prompt_message="Press Enter to continue"
        else
            prompt_message="$custom_message"
        fi
        prompt_options="[Enter]"
    elif [[ "$default_yes" == true ]]; then
        if [[ -z "$custom_message" ]]; then
            prompt_message="Are you sure you want to continue"
        else
            prompt_message="$custom_message"
        fi
        prompt_options="[Y/n]"
    elif [[ "$default_no" == true ]]; then
        if [[ -z "$custom_message" ]]; then
            prompt_message="Are you sure you want to continue"
        else
            prompt_message="$custom_message"
        fi
        prompt_options="[y/N]"
    else
        if [[ -z "$custom_message" ]]; then
            prompt_message="Are you sure you want to continue"
        else
            prompt_message="$custom_message"
        fi
        prompt_options="[y/n]"
    fi
    if [[ ! "$no_report" == true ]]; then
        send_report "Waiting for client user input: ${custom_message}${prompt_options}"
    fi
    while true; do
        echo -e -n "${prompt_message} ${prompt_options} "
        read input_text
        # For -e option, any non-empty input is treated as an 'enter'
        if [[ "$expect_enter" == true ]]; then
            return 0
        fi
        # Convert input to lowercase for case-insensitive comparison
        local response="${input_text,,}"
        if [[ -z "$response" ]]; then
            if [[ "$default_yes" == true ]]; then
                return 0
            elif [[ "$default_no" == true ]]; then
                return 1
            fi
        fi
        if [[ "$response" == "y" || "$response" == "yes" ]]; then
            return 0
        elif [[ "$response" == "n" || "$response" == "no" ]]; then
            return 1
        fi
        echo "Invalid input. Please enter 'y', 'yes', 'n', or 'no'."
    done
}

# A function to set the integer value of the CHECKPOINT variable in the checkpoint_file.
# Returns:
#   Nothing. The function exits with a status code (0 for success, non-zero for error).
# Usage:
#   set_checkpoint 2
function set_checkpoint() {
    if [[ -z "$1" ]]; then
        echo "Error: No checkpoint value provided. Please provide a non-negative integer." >&2
        return 1
    fi
    local new_checkpoint="$1"
    if ! [[ "$new_checkpoint" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid checkpoint value. Must be a non-negative integer." >&2
        return 1
    fi
    if [ ! -f "$checkpoint_file" ]; then
        local current=0
    else
        local current=$(grep "^CHECKPOINT=" "$checkpoint_file" | cut -d'=' -f2)
    fi
    if [[ $new_checkpoint -gt $current ]]; then
        echo "CHECKPOINT=$new_checkpoint" > "$checkpoint_file"
    fi
}

# A function to retrieve the integer value of the CHECKPOINT variable from the checkpoint_file.
# Returns:
#   The integer value of the CHECKPOINT.
# Usage:
#   current_checkpoint=$(get_checkpoint)
function get_checkpoint() {
    # Check if the file exists
    if [ ! -f "$checkpoint_file" ]; then
        echo ""
        return 1
    fi
    local raw_value=$(grep "^CHECKPOINT=" "$checkpoint_file" | cut -d'=' -f2)
    if [[ -z "$raw_value" ]]; then
        echo "Error: CHECKPOINT variable not found in the file." >&2
        return 1
    fi
    if ! [[ "$raw_value" =~ ^[0-9]+$ ]]; then
        echo "Error: The value for CHECKPOINT is not a non-negative integer." >&2
        return 1
    fi
    echo "$raw_value"
}

## Get the path to the write divice (ex. "/dev/mmcblk0") from cache
function get_device() {
    # Check if the file exists
    if [ ! -f "$install_device_file" ]; then
        echo ""
        return 1
    fi
    cat ${install_device_file}
}

function generate_install_id() {
    if [ ! -f "$install_id_file" ]; then
        echo "$(LC_TIME=C date +%y-%b-%d)-$(cat /dev/urandom | tr -dc 'a-z' | head -c 6)" > ${install_id_file}
        echo -e "${T_BLUE}New installation started${T_NC}"
        new_install=true
    else
        echo -e "${T_BLUE}Continuing previous installation${T_NC}"
    fi
}

function get_install_id() {
    if [ ! -f "$install_id_file" ]; then
        echo ""
        return 1
    fi
    cat ${install_id_file}
}

function send_report(){
    local message=$1
    ${base_dir}/common/report_install_progress.sh "${api_domain}${endpoint_report_install}" "${install_id}" "${message}"
    if [[ $? -ne 0 ]]; then
        echo -e "${T_YELLOW}Warning: Failed to report status to the server.${T_NC}"
    fi
}

## Tests if actual IP of Raspberry Pi matches the configuration IP
function verify_ip() {
    local online_ip=$1
    local config_ip=$2
    if [[ "$online_ip" == "$config_ip" ]]; then
        echo -e "${T_GREEN}Current IP is '${online_ip}' matches the IP in configuration${T_NC}"
        return 0
    else
        echo -e "${T_YELLOW}Current IP '${online_ip}' does not match the IP in configuration '${RPI_IP_ADDR}'${T_NC}"
        return 1
    fi
}

# Save Raspberry Pi configuration to file
function userdata_save_config(){
    source ${configuration_file}
    RPI_CONFIG_FILE="${config_memos_dir}/${RPI_CONFIG_NAME}_raspberrypi-config.txt"
    rm -f "$RPI_CONFIG_FILE"
    ${base_dir}/utils/print_config.sh "${configuration_file}" "true" >> $RPI_CONFIG_FILE
    echo -e "${T_ITALIC}These data was saved to ${RPI_CONFIG_FILE}${T_NC}"
    echo -e "${T_ITALIC}You can save this file for future reference${T_NC}"
    get_user_input -e
}

# Save router configuration to file
function userdata_save_router_config(){
    ROUTER_CONFIG_INSTRUCTION_FILE="${config_memos_dir}/${RPI_CONFIG_NAME}_router-config.txt"
    rm -f "$ROUTER_CONFIG_INSTRUCTION_FILE"
    ${base_dir}/utils/print_router_config.sh "${configuration_file}" $DEVICE_MAC $DEVICE_INTERFACE "true" >> $ROUTER_CONFIG_INSTRUCTION_FILE
    echo -e "${T_ITALIC}These instructions were saved to ${ROUTER_CONFIG_INSTRUCTION_FILE}${T_NC}"
    echo -e "${T_ITALIC}You can save this file for future reference${T_NC}"
    get_user_input -e
}

# Test IP provided by the user
function get_mac_address(){
    local ip=$1
    network_info=$(timeout 5 ip neigh show "$ip" | awk 'NF>=5 {print $3, $5}')
    if [[ -n "$network_info" ]]; then
        # Split the string into separate variables.
        read -r found_interface found_mac <<< "$network_info"
        DEVICE_MAC=$found_mac
        DEVICE_INTERFACE=$found_interface
        echo -e "${T_BLUE}MAC address and network interface found${T_NC}"
        return 0
    else
        echo -e "${T_RED}Error: Could not find a device with that IP address or it is unreachable.${T_NC}"
        return 1
    fi
}

function print_test_progress(){
    local current_test=$1
    local total_tests=$2
    echo -e "${T_BLUE}--- Test ${current_test}/${total_tests}${T_NC}"
    echo -e "Test ${current_test}/${total_tests}" >> "$userdata_test_file"
}

# A function to get the number of lines srarting with a string prefix from a string line
# Returns:
#   The integer number of lines.
# Usage:
#   count_lines <LINE> <PREFIX>
function count_lines() {
    echo "$1" | grep -c "^$2" | tr -d ' '
}

# Loop through command-line arguments.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|-V|--v|--V|--version)
            echo "${script_version}"
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --update)
            ${base_dir}/update.sh
            exit 0
            ;;
        --uninstall)
            get_user_input -l "This will remove ${app_name}, clean up persistent data, caches, environment variables and symlinks. Do you want to continue?"
            ${base_dir}/uninstall.sh
            exit 0
            ;;
        --media)
            shift
            if [[ ! -z "$1" ]]; then
                option_install_media="$1"
                shift
            else
                echo "Device path is empty. Usage with option media example: ${binary_name} --media /dev/mmcblk0"
                exit 1
            fi
            ;;
        --no-checkpoints|--nc|--restart|-r)
            get_user_input -l "This will remove previous installation's data. Do you want to continue?"
            rm -f ${checkpoint_file}
            rm -f ${install_device_file}
            rm -f ${configuration_file}
            rm -f ${install_id_file}
            echo "Previous installation data removed"
            exit 0
            ;;
        -*)
            # Handle any unknown options.
            echo "Error: Unknown option: '$1'" >&2
            show_help
            exit 1
            ;;
    esac
done


# Check main arguments
if [[ ! -z "$1" && ! -z "$2" && ! -z "$3" ]]; then
    api_domain="$1"
    api_key="$2"
    crypto_key="$3"
    shift
    shift
    shift
    api_domain="${api_domain%${endpoint_install}}"
else
    if [[ -z "$WORMHOLE_API_KEY" || -z "$WORMHOLE_API_URL" || -z "$WORMHOLE_CRYPTO_KEY" ]]; then
        echo "Error: WORMHOLE_API_URL or WORMHOLE_API_KEY or WORMHOLE_CRYPTO_KEY are missing in the environment. The URL, TOKEN and CRYPTO_KEY must be provided as command-line arguments." >&2
        echo "Usage: sudo bash ${binary_name} [options] <URL> <TOKEN> <CRYPTO_KEY>" >&2
        exit 1
    else
        api_domain=$WORMHOLE_API_URL
        api_key=$WORMHOLE_API_KEY
        crypto_key="$WORMHOLE_CRYPTO_KEY"
    fi
fi


# Init state
API_HOST_OK=false
API_SERVER_STATUS="unknown"
INTERNET_OK=false
DEPENDENCIES_CHECKED=false
INSTALL_DEVICE=""
CONFIG_READY=false
FIRSTRUN_READY=false
IMAGE_WRITTEN=false
DEVICE_REACHABLE=false
ROUTER_CONFIGURED=false
CONFIG_UPLOADED=false
AUTOINSTALL_DONE=false
DEVICE_MAC=""
DEVICE_INTERFACE=""
ROUTER_CONFIG_INSTRUCTION_FILE=""

server_pollrate=250
install_user=""
install_user_ip=""
install_id=""
new_install=false

sudo -v

if [ ! -d "${persistent_data_dir}" ]; then
    mkdir -p ${persistent_data_dir}
    chmod u+w ${persistent_data_dir}
    mkdir -p ${config_memos_dir}
    chmod u+w ${config_memos_dir}
fi


## Export functions anv variables for child scripts
export -f get_user_input
export -f send_report
export base_dir
export api_domain
export endpoint_report_install
export install_id
export install_user
export install_user_ip

## ============================================================
## Checklist
## ============================================================

## ============================================================
## 0. Present first launch info
## ============================================================
if [ -f "${base_dir}/hello.sh" ]; then
    new_install=true
    ${base_dir}/hello.sh "${binary_name}" "${persistent_data_dir}" "${app_name} ${script_version}"
    rm -f ${base_dir}/hello.sh
    echo
    get_user_input -e -l
fi

tput clear

print_header

## ============================================================
## 1 - 2. Internet connection check
## ============================================================
echo -e "${T_BLUE}[1/3] Checking internet connection...${T_NC}"
for host in "${test_hosts[@]}"; do
    echo -e "Pinging ${host} ..."
    if ping -c 1 -W "$ping_timeout" "$host" >/dev/null 2>&1; then
        INTERNET_OK=true
        echo -e "${T_GREEN}\tOnline${T_NC}"
        break
    fi
    echo -e "${T_YELLOW}\tcan't reach ${host}${T_NC}"
done
if [[ ! $INTERNET_OK == "true" ]]; then
    echo -e "${T_RED}\tInternet offline${T_NC}"
    exit 1
fi
install_user_ip=$(nmcli -t -f IP4.ADDRESS device show | head -1 | cut -d"/" -f1 | cut -d : -f2)
echo -e "\tUser's local IP address: ${install_user_ip}"
echo -e "${T_BLUE}[2/3] Checking connection to the API server...${T_NC}"
API_SERVER_STATUS=$(curl -s -f "${api_domain}${endpoint_health}" | grep -o '"status":"[^"]*"' | cut -d: -f2 | tr -d '"' 2>/dev/null)
if [[ $API_SERVER_STATUS == "healthy" ]]; then
    echo -e "${T_GREEN}\tServer status: ${API_SERVER_STATUS}${T_NC}"
else
    echo -e "${T_YELLOW}\tServer status: ${API_SERVER_STATUS}${T_NC}"
fi
server_pollrate=$(${base_dir}/utils/get_request.sh "${api_domain}${endpoint_get_pollrate}" "${api_key}")
result=$?
if [ $result -eq 0 ]; then
    echo -e "\tServer pollrate: ${server_pollrate} ms"
else
    echo -e "${T_YELLOW}\tFailed to get pollrate from the server.${T_NC}"
fi
echo -e "${T_BLUE}[3/3] Requesting username from the server...${T_NC}"
install_user=$(${base_dir}/utils/get_request.sh "${api_domain}${endpoint_get_username}" "${api_key}")
result=$?
if [ $result -eq 0 ]; then
    echo -e "${T_GREEN}\tIdentified user: ${install_user}${T_NC}"
else
    echo -e "${T_YELLOW}\tFailed to get user ID from the server. Using 'default' user.${T_NC}"
fi
if [[ $new_install == "true" ]]; then
    get_user_input -e -l
fi

tput clear
expect_progress 2

## ============================================================
## 3. Generate installid file for reporting
## ============================================================
generate_install_id
install_id=$(get_install_id)
echo -e "Instance ${T_BLUE}${install_id}${T_NC}"
echo -e "${T_ITALIC}This script will report some steps off the installation to the server.${T_NC}"
echo -e "${T_ITALIC}This ID can be referred to in the server's logs for troubleshooting.${T_NC}"
if [[ $new_install == "true" ]]; then
    send_report "${install_user} Started a brand new installation"
else
    send_report "${install_user} Re-started the installer script"
fi
if [[ $? -eq 0 ]]; then
    echo -e "${T_GREEN}Reporting to the server is working as expected.${T_NC}"
    send_report "User ${install_user} running installation ${install_id}"
else
    if [[ $PROCEED_WITHOUT_LOGGING == "true" ]]; then
        echo -e "${T_YELLOW}Warning: Reporting to the server is failing.${T_NC}"
    else
        echo -e "${T_RED}Error: Reporting to the server is failing. Fix the connection or set PROCEED_WITHOUT_LOGGING=true${T_NC}"
        exit 1
    fi
fi

CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 3)); then
    get_user_input -e
else
    set_checkpoint 3
fi

tput clear
expect_progress 3

## ============================================================
## 4. Dependencies
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 4)); then
    if [[ "$SKIP_DEPENDENCIES" != "true" ]]; then
        send_report "Starting depencency installation"
        ${base_dir}/utils/install_dependencies.sh
        result=$?
        if [[ result -eq 0 ]]; then
            DEPENDENCIES_CHECKED=true
            send_report "Depencency installation success"
        else
            echo -e "${T_RED}Error: Dependency install was failed."
            send_report "Depencency installation failed"
            exit 1
        fi
    else
        echo -e "${T_BYELLOW}Warning: Dependency check was skipped - this might cause the script to fail later.${T_NC}"
        echo -e "${T_BYELLOW} - This is a debug feature. To reenable the check, set SKIP_DEPENDENCIES to false.${T_NC}"
        DEPENDENCIES_CHECKED=true
        send_report "Depencency installation skipped"
    fi
    if [[ "$DEPENDENCIES_CHECKED" == "true" ]]; then
        set_checkpoint 4
        get_user_input -e
    fi
else
    set_checkpoint 4
    DEPENDENCIES_CHECKED=true
fi

tput clear
expect_progress 4

## ============================================================
## 5. Get configuration
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 5)); then
    if [ -f "$configuration_file" ]; then
        echo "Found existing configuration at ${configuration_file}"
        ${base_dir}/utils/validate_config.sh "${configuration_file}"
        valid=$?
        if [ $valid -eq 0 ]; then
            set_checkpoint 5
            exit 0
            CONFIG_READY=true
            source ${configuration_file}
            send_report "Previous configuration loaded"
        else
            CONFIG_READY=false
        fi
    fi
    # If failed to find a valid config, request from the server
    if [[ ! $CONFIG_READY == true ]]; then
        echo "No valid configuration found at ${configuration_file} ..."
        ${base_dir}/utils/get_config.sh "${api_domain}${endpoint_get_config}" "${api_key}" "${configuration_file}"
        result=$?
        if [[ $result -eq 0 ]]; then
            echo -e "${T_GREEN}Configuration retrieved from the server.${T_NC}"
        else
            ${base_dir}/utils/print_config.sh "${configuration_file}"
            echo -e "${T_YELLOW}There was a problem retrieving configuration data.${T_NC}"
            get_user_input -e
            exit 1
        fi
        # Validate retrieved configuration
        ${base_dir}/utils/validate_config.sh "${configuration_file}"
        if [ $? -eq 0 ]; then
            CONFIG_READY=true
            set_checkpoint 5
            ${base_dir}/utils/print_config.sh "${configuration_file}"
        else
            get_user_input -e
            exit 1
        fi
    fi
    userdata_save_config
else
    set_checkpoint 5
    CONFIG_READY=true
    source ${configuration_file}
fi
send_report "Configuration ready and validated"

tput clear
expect_progress 5
${base_dir}/utils/print_config.sh "${configuration_file}"

## ============================================================
## 6. Set install media
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 6)); then
    # Attempt getting a valid device from the command option
    if [[ ! -z "$option_install_media" ]]; then
        if [[ -b "$option_install_media" ]]; then
                INSTALL_DEVICE="$option_install_media"
                echo ${INSTALL_DEVICE} > ${install_device_file}
                echo -e "${T_GREEN}'$INSTALL_DEVICE' is valid block device.${T_NC}"
        else
                echo -e "${T_YELLOW}'$option_install_media' is not a valid block device. Please pick another.${T_NC}"
        fi
    fi
    # Attempt getting a cached device path
    INSTALL_DEVICE=$(get_device)
    if [ ! -z "$INSTALL_DEVICE" ]; then
        # Check in case the path is obsolete
        if [[ ! -b "$INSTALL_DEVICE" ]]; then
            echo -e "${T_RED}Error: Media ${INSTALL_DEVICE} is not currently connected.${T_NC}"
            INSTALL_DEVICE=""
        fi
    fi
    if [ -z "$INSTALL_DEVICE" ]; then
        # Check filesystem
        echo -e "${T_BBLUE}Available disks:${T_NC}"
        lsblk -o PATH,TYPE,VENDOR,MODEL,SIZE | grep disk | grep -v zram
        avail_disks=$(lsblk -o PATH,TYPE,VENDOR,MODEL,SIZE | grep disk | grep -v zram)
        disk_count=$(echo "$avail_disks" | wc -l)
        if [ "$disk_count" -eq 1 ]; then
            echo -e "${T_RED}Warning: There's only one disc available. Stopping to prevent overwriting the system drive.${T_NC}"
            echo -e "${T_RED}Please connect the install media and re-run the script.${T_NC}"
            send_report "Exiting because only one block device was discovered during the media selection."
            exit 1
        fi
        # Loop until a valid device path is provided.
        send_report "Waiting for install media to be selected by the client."
        while true; do
            echo -e "${T_BBLUE}Please enter the device path:${T_NC} ${T_ITALIC}(example /dev/mmcblk0)${T_NC}"
            read -e -i "/dev/" input_path
            # The `-b` test checks if the file exists and is a block device.
            if [[ -b "$input_path" ]]; then
                INSTALL_DEVICE="$input_path"
                echo ${INSTALL_DEVICE} > ${install_device_file}
                echo -e "${T_GREEN}'$INSTALL_DEVICE' is valid block device.${T_NC}"
                send_report "Device picked $(lsblk -o PATH,TYPE,VENDOR,MODEL,SIZE | grep ${INSTALL_DEVICE} | grep disk)"
                install_device_friendly=$(lsblk -o PATH,VENDOR,MODEL,SIZE,TYPE | grep disk | grep ${INSTALL_DEVICE})
                echo -e "${T_YELLOW}All data currently on this device will be lost.${T_NC}"
                echo -e "${install_device_friendly}"
                get_user_input "Do you confirm?"
                if [[ $? -eq 0 ]]; then
                    break
                fi
            else
                echo -e "${T_RED}Error: '$input_path' is not a valid block device or does not exist.${T_NC}"
                echo "Please try again."
            fi
        done
    fi
    set_checkpoint 6
else
    set_checkpoint 6
    INSTALL_DEVICE=$(cat ${install_device_file})
fi
send_report "Install media ready"

tput clear
expect_progress 6
${base_dir}/utils/print_config.sh "${configuration_file}"

## ============================================================
## 7. Customize firstrun.sh
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 7)); then
    ${base_dir}/utils/customize_firstrun.sh "${configuration_file}" "${firstrun_template_file}" "${firstrun_file}" ${crypto_key}
    result=$?
    if [[ $result -eq 0 ]]; then
        FIRSTRUN_READY=true
        echo -e "\n${T_GREEN}firstrun.sh script created at "${firstrun_file}"${T_NC}"
        send_report "firstrun.sh ready"
        get_user_input -e
        set_checkpoint 7
    else
        echo -e "${T_BRED}Error: Failed to create a firstrun script at "${firstrun_file}"${T_NC}"
        exit 1
    fi
else
    set_checkpoint 7
    FIRSTRUN_READY=true
fi

tput clear
expect_progress 7
${base_dir}/utils/print_config.sh "${configuration_file}"

## ============================================================
## 8-9. Unmount volumes and Image the SD-card
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 9)); then
    send_report "Starting the write image sequence"
    echo -e "${T_BLUE}Image settings complete${T_NC}"
    echo "All partitions from device ${INSTALL_DEVICE} have to be unmounted before writing the image"
    echo -e "${T_YELLOW}Please close all files opened from this device before continuing.${T_NC}"
    get_user_input -e
    ${base_dir}/utils/unmount_partitions.sh ${INSTALL_DEVICE}
    result=$?
    if [[ ! $result -eq 0 ]]; then
        echo -e "${T_BRED}Error: Can't write to the device that is currently being used.${T_NC}"
        send_report "Failed to gain access to the partition"
        exit 1
    fi
    set_checkpoint 8
    # Run the imager
    echo
    ${base_dir}/utils/imager.sh "$INSTALL_DEVICE" "${RPI_CONFIG_TAG}" "${RPI_CONFIG_SEARCH}" "${RPI_CONFIG_TIMEOUT}" "${firstrun_file}"
    result=$?
    if [[ $result -eq 0 ]]; then
        IMAGE_WRITTEN=true
        set_checkpoint 9
        send_report "Image successfully written to client's media. Instructed the client to power on the device."
        echo -e "${T_GREEN}OS image written to ${INSTALL_DEVICE}\nIt is safe to remove now.${T_NC}"
        get_user_input -e "${T_BOLD}Please insert the media into Raspberry Pi and power it on. If you are using a wired network connection, also connect the Ethernet cable${T_NC}"
        get_user_input -e "${T_YELLOW}Press if the Raspberry Pi is powered on and expected to be accessible on the network.${T_NC}"
        send_report "Client confirmed powering on the device"
    else
        echo -e "${T_RED}Error: imager.sh has failed"
        send_report "imager.sh has failed"
        exit 1
    fi
else
    set_checkpoint 9
    IMAGE_WRITTEN=true
fi

tput clear
expect_progress 9

## ============================================================
## 10. Wait for Pi to appear online
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 10)); then
    source ${configuration_file}
    online_ip=""
    ## Attempt to automatically find Raspberry Pi on the local network via mDNS hostname
    send_report "Attempting to find RPi online via the mDNS hostname"
    ${base_dir}/utils/wait_for_host.sh "${RPI_HOSTNAME}.local" 600
    if [[ $? -eq 0 ]]; then
        DEVICE_REACHABLE=true
        ## Retrieve IP address
        online_ip=$(ping -c 1 -W 10 "${RPI_HOSTNAME}.local" | grep 'bytes of data' | awk '{print $3}' | cut -d'(' -f2 | cut -d ')' -f1)
        echo -e "\n${T_GREEN}Device found and is reachable on the network at ${online_ip}${T_NC}"
        send_report "Device discovered on local network by client via mDNS"
        get_user_input -e
    else
        DEVICE_REACHABLE=false
        echo -e "${T_RED}Error: Can't reach ${RPI_HOSTNAME}.local on the network${T_NC}"
        send_report "Client failed to discover the device on local network via mDNS"
    fi
    ## If no success, continue manually
    if [[ ! "$DEVICE_REACHABLE" == true ]]; then
        # A loop until a valid IP address and device are provided by the user.
        send_report "Asking the user to type in the correct IP address"
        while true; do
            # Show neighbours and prompt the user to enter the IP address.
            echo -e "${T_BLUE}Please type in the IP of your Raspberry Pi manually.${T_NC}"
            echo "Devices on your local network:"
            ip -4 neigh show
            read -p "Please enter a valid IP address manually: " user_input
            if [[ -z "$user_input" ]]; then
                echo "IP address cannot be empty. Please try again."
                continue
            fi
            ping -c 1 -W 1 "$user_input" &> /dev/null
            if [[ $? -eq 0 ]]; then
                DEVICE_REACHABLE=true
                # Retrieve IP address
                online_ip=$(ping -c 1 -W 10 "${user_input}" | grep 'bytes of data' | awk '{print $3}' | cut -d'(' -f2 | cut -d ')' -f1)
                echo -e "\n${T_GREEN}Device found and is reachable on the network at ${online_ip}${T_NC}"
                ip -r neigh show $online_ip
                send_report "Device was manually located on client's local network"
                get_user_input -e
                break
            fi
        done
    fi
    if [[ ! "$DEVICE_REACHABLE" == true ]]; then
        echo -e "${T_RED}Error: Failed to find Raspberry Pi on the network.${T_NC}"
        send_report "Failed to find Raspberry Pi on client's local network"
        exit 1
    else
        verify_ip $online_ip $RPI_IP_ADDR
        result=$?
        if [[ $result -eq 0 ]]; then
            send_report "IP address matches the one in the configuration"
            get_user_input -e
        else
            send_report "IP address does not match the one in the configuration"
            while true; do
                echo -e "${T_BLUE}How do you with to proceed?${T_NC}"
                echo "  1. Update the configuration to match the current IP assigned by router's DHCP - '${online_ip}'"
                echo "  2. Keep the configuration's IP address and reconfigure the router later"
                read -p "Choose an option: " option
                # Based on user option, proceed with IP configuration
                if [[ $option -eq 1 ]]; then
                    RPI_IP_ADDR=$online_ip
                    # Update configuration file with DHCP IP
                    sed -i "s/RPI_IP_ADDR=.*/RPI_IP_ADDR='$online_ip'/" $configuration_file
                    echo -e "${T_BLUE}Configuration updated${T_NC}"
                    userdata_save_config
                    send_report "Client has updated the configuration with a new IP address"
                    break
                elif [[ $option -eq 2 ]]; then
                    echo -e "${T_YELLOW}Configuration IP will be kept. Please reconfigure the router later.${T_NC}"
                    send_report "Client promted to keep configuration unchanged. Expecting changes in the router settings."
                    get_user_input -e
                    break
                else
                    echo -e "${T_YELLOW}Invalid option. Please enter 1 or 2.${T_NC}"
                fi
            done
        fi
    fi
    get_mac_address $online_ip
    send_report "Client identified the device: $online_ip MAC address ${DEVICE_MAC} (${DEVICE_INTERFACE})"
    set_checkpoint 10
else
    source ${configuration_file}
    ping -c 1 -W 1 "${RPI_IP_ADDR}" &> /dev/null
    if [[ $? -eq 0 ]]; then
        online_ip=$RPI_IP_ADDR
        DEVICE_REACHABLE=true
        get_mac_address $RPI_IP_ADDR
        send_report "Client identified the device: $RPI_IP_ADDR MAC address ${DEVICE_MAC} (${DEVICE_INTERFACE})"
        set_checkpoint 10
    else
        send_report "Client failed to confirm that Raspberry Pi is online at the IP address provided in configuration."
    fi
fi

tput clear
expect_progress 10

## ============================================================
## 11-12. Ask the user to configure the router. Run tests
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 12)); then
    TESTS_PASSED=true
    router_ip=$(ip route | grep default | awk '{print $3}')
    send_report "Router ${router_ip} configuration settings were provided to the user.\nUser prompted to configure and reboot the router."
    echo -e "${T_BOLD}Please configure your router${T_NC}"
    ${base_dir}/utils/print_router_config.sh "${configuration_file}" "${DEVICE_MAC}" "${DEVICE_INTERFACE}"
    userdata_save_router_config
    echo
    # Wait for confirmation
    get_user_input -e "${T_BOLD}Reboot the router and continue after it boots back up${T_NC}"
    get_user_input -e "${T_YELLOW}Did you configure and reboot the router? If yes, press${T_NC}"
    # Set up for tests and logging
    source ${configuration_file}
    ports_to_check="${RPI_SSH_PORT},${RPI_WH_PORT}"
    userdata_test_file="${config_memos_dir}/${RPI_CONFIG_NAME}_tests.txt"
    total_tests=5
    # Perfom tests and log outputs
    echo -e "${T_BOLD}Running tests to confirm everything is working${T_NC}"
    # Wait for network to turn back on
    print_test_progress 1 ${total_tests}
    ${base_dir}/utils/wait_for_host.sh $router_ip 600 "Router" 2>&1 > >(tee -a "$userdata_test_file")
    result=$?
    if [[ $result -ne 0 ]]; then
        echo -e "${T_RED}Status: Failed to reconnect to the router${T_NC}"
        TESTS_PASSED=false
        exit 1
    fi
    # Wait for internet to turn back on
    print_test_progress 2 ${total_tests}
    test_is_online=false
    for host in "${test_hosts[@]}"; do
        ${base_dir}/utils/wait_for_host.sh ${host} 200 "Internet" 2>&1 > >(tee -a "$userdata_test_file")
        result=$?
        if [[ $result -eq 0 ]]; then
            test_is_online=true
            send_report "Router back online after client confirmed that the router was configured and rebooted"
            break
        fi
    done
    if [[ "$test_online" == false ]]; then
        echo -e "${T_RED}Status: Failed to reconnect to the internet${T_NC}"
        TESTS_PASSED=false
        exit 1
    fi
    # Wait for Raspberry Pi
    print_test_progress 3 ${total_tests}
    ${base_dir}/utils/wait_for_host.sh $RPI_IP_ADDR 120 "Raspberry Pi" 2>&1 > >(tee -a "$userdata_test_file")
    result=$?
    if [[ $result -eq 0 ]]; then
        send_report "Raspberry Pi accessible by the client on the configured IP address"
    else
        TESTS_PASSED=false
        send_report "Raspberry Pi is not accessible by the client on the configured IP address"
    fi
    # Check ssh port
    print_test_progress 4 ${total_tests}
    nmap_output=$(nmap -p $ports_to_check $RPI_IP_ADDR -oG - 2>/dev/null)
    if echo "$nmap_output" | grep -q "${RPI_SSH_PORT}/open"; then
        echo -e "${T_GREEN}Status: Configured SSH port is open${T_NC}"
        echo "Status: Configured SSH port is open" >> "$userdata_test_file"
        send_report "Configured SSH port is open"
    else
        echo -e "${T_RED}Status: Failed: Configured SSH port not open${T_NC}"
        echo "Status: Failed: Configured SSH port not open" >> "$userdata_test_file"
        send_report "Configured SSH port not open"
        TESTS_PASSED=false
    fi
    # Check domain
    print_test_progress 5 ${total_tests}
    if [[ ! -z "$RPI_DOMAIN" ]]; then
        ${base_dir}/utils/wait_for_host.sh ${RPI_DOMAIN##*://} 120 "${RPI_DOMAIN##*://}" 2>&1 > >(tee -a "$userdata_test_file")
        result=$?
        if [[ $result -eq 0 ]]; then
            send_report "Raspberry Pi accessible by the client on the configured domain"
        else
            TESTS_PASSED=false
            send_report "Raspberry Pi is not accessible by the client on the configured domain"
        fi
    fi
    # Resolve stage status
    if [[ $TESTS_PASSED == "true" ]]; then
        ROUTER_CONFIGURED=true
        set_checkpoint 12
    fi
    get_user_input -e
else
    ROUTER_CONFIGURED=true
    set_checkpoint 12
fi

tput clear
expect_progress 12

## ============================================================
## 13. Upload device configuration to the API server
## ============================================================
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 13)); then
    source ${configuration_file}
    send_report "Trying to upload configuration for ${RPI_CONFIG_NAME} - ${install_id}"
    ${base_dir}/utils/upload_config.sh "${configuration_file}" "${api_domain}${endpoint_upload_config}" "${api_key}" "${crypto_key}" "${crypto_cipher}" "${key_derivation}"
    result=$?
    if [[ $result -eq 0 ]]; then
        send_report "Recieved confirmation from the server that ${RPI_CONFIG_NAME} - ${install_id} was uploaded."
        CONFIG_UPLOADED=true
        set_checkpoint 13
    else
        send_report "Error: Failed to upload ${RPI_CONFIG_NAME} - ${install_id}."
    fi
    get_user_input -e
else
    CONFIG_UPLOADED=true
    set_checkpoint 13
fi

tput clear
expect_progress 13

## ============================================================
## 14. Monitor auto install progress
## ============================================================
install_log_file="${config_memos_dir}/${RPI_CONFIG_NAME}_install_log_${install_id}.log"
CHECKPOINT=$(get_checkpoint)
if (( CHECKPOINT < 14)); then
    #     #AUTOINSTALL_DONE=true
    #     #set_checkpoint 14
    source ${configuration_file}
    default_rpi_hostname="raspberrypi"
    max_requests_limit=54000 # (3 hours at 0.2 pollind rate)
    last_update_time=0
    poll_rate=$(echo "scale=3; ${server_pollrate} / 1000" | bc)
    poll_rate_wait=3
    output_prefix="> "
    current_log_line=1
    current_install_progress=0
    # Markers (hard-coded on the server)
    marker_wait="___ WAITING ___"
    marker_fin="___ FINISHED ___"
    marker_progress="___ PROGRESS ___"
    marker_state="___ STATE ___"
    marker_close="___"
    progress_bar_length=65
    # Init new log file
    echo "#########################################################################" > "${install_log_file}"
    echo "##                              INSTALL LOG" >> "${install_log_file}"
    echo "##  This is an install log that contains records from both the installer" >> "${install_log_file}"
    echo "##  client and the Raspberry Pi itself." >> "${install_log_file}"
    echo "##             Installation instance ${install_id}" >> "${install_log_file}"
    echo "#########################################################################" >> "${install_log_file}"
    # Start polling the server
    send_report "Starting to pull the installation log from the server."
    echo -e "${T_BOLD}Connecting to ${api_domain}${endpoint_read_install}${T_NC}"
    requests_left=$max_requests_limit
    log_state="Installing on Pi..."
    while true; do
        wait_time=$poll_rate
        response=$(${base_dir}/common/read_install_progress.sh "${api_domain}${endpoint_read_install}" "${install_id}" "${current_log_line}" "${output_prefix}")
        if [ -n "$response" ]; then
            log_line=$(echo "$response" | head -n -1)
            log_status=$(echo "$response" | tail -n 1)
            if echo "$response" | grep -q "${marker_wait}"; then
                wait_time=$poll_rate_wait
            elif echo "$response" | grep -q "${marker_state}"; then
                log_state=$(echo "${log_line}" | grep -oP "(?<=${marker_state}).*?(?=${marker_close})")
                current_log_line=$((current_log_line + received_lines))
            elif echo "$response" | grep -q "${marker_progress}"; then
                progress=$(echo "${log_line}" | grep -oP "(?<=${marker_progress}).*?(?=${marker_close})")
                if [[ -n "$progress" ]] && [[ "$progress" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    if awk -v prog="$progress" 'BEGIN { if (prog >= 0 && prog <= 100) exit 0; else exit 1 }'; then
                        current_install_progress=$progress
                    else
                        send_report "Irregular progress value received ${progress}"
                    fi
                else
                    send_report "Irregular progress value received ${progress}"
                fi
                current_log_line=$((current_log_line + 1))
            elif echo "$response" | grep -q "${marker_fin}"; then
                printf "\033[K${T_GREEN}${output_prefix}%s${T_NC}\n" "Log complete"
                send_report "Finished streaming the log"
                AUTOINSTALL_DONE=true
                break
            else
                received_lines=$(count_lines "${response}" "${output_prefix}")
                current_log_line=$((current_log_line + received_lines))
                last_update_time=0
                echo "${log_line}" >> "${install_log_file}" # Write log to file
                new_log_line="${log_line/\[$(hostname -s)\]/${T_BLUE}[$(hostname -s)]${T_NC}}" # Color-code hostname local client
                new_log_line="${new_log_line/\[${RPI_HOSTNAME}\]/${T_GREEN}[${RPI_HOSTNAME}]${T_NC}}"  # Color-code hostname RPi configured
                new_log_line="${new_log_line/\[${default_rpi_hostname}\]/${T_MAGENTA}[${default_rpi_hostname}]${T_NC}}" # Color-code hostname RPi default
                printf "\033[K${new_log_line}\033[K\n" # Write to the terminal
            fi
            # Calculate last update time
            last_update_time=$(echo "scale=2; ${last_update_time} + ${wait_time}" | bc)
            # Clear the line from the cursor to the end, then print the updated status.
            printf "\033[K${T_BLUE}${output_prefix}%s${T_NC} (last update %s seconds ago)\n" "${log_status}" "${last_update_time}"
            print_progressbar "$current_install_progress" "$progress_bar_length" "$log_state" 7
            printf "\033[2A"
        fi
        sleep "${wait_time}"
        requests_left=$((requests_left - 1))
        # Check if request limit was reached yet
        if [[ $requests_left -le 0 ]]; then
            printf "\033[K"
            echo -e "${T_YELLOW}Warning: Reached the limit of ${max_requests_limit} requests. Log is incomplete."
            break
        fi
    done
    # Final message after the log
    printf "\033[K\n\n"
    if [[ $AUTOINSTALL_DONE == "true" ]]; then
        echo -e "${T_GREEN}Installation finished!${T_NC}"
        send_report "Client finished pulling the log. Marking the install as finished."
        set_checkpoint 14
    else
        echo -e "${T_GREEN}Installation finished ${T_YELLOW}with warnings.${T_NC}"
        send_report "Client finished pulling the log. Errors found. Marking the install as unfinished."
    fi
    echo -e "${T_ITALIC}Install log saved to ${install_log_file}${T_NC}"
    echo
    get_user_input -e "${T_BLUE}Press to exit the installer${T_NC}"
else
    AUTOINSTALL_DONE=true
fi

tput clear
expect_progress 14

## ============================================================
## 15. Fin
## ============================================================
echo -e "${T_GREEN}Installation completed. Thank you!${T_NC}"
echo -e "${T_ITALIC}Log saved to ${install_log_file}${T_NC}"
exit 0