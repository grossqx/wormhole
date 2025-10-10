#!/bin/bash

package_list_dependency="bc jq"

package_list_additional="nmap nfs-kernel-server ffmpeg mc"

repositories_to_clone=(
    "https://github.com/geerlingguy/rpi-clone.git"
)

third_party_scripts=(
    "https://raw.githubusercontent.com/geerlingguy/pi-cluster/refs/heads/master/benchmarks/disk-benchmark.sh"
    "https://download.argon40.com/argon1.sh"
)

dependencies=(
    "/etc/environment"
    "/etc/profile.d/rpi_sysinfo.sh"
    "/etc/profile.d/wh_logger.sh"
    "/etc/profile.d/wh_storage.sh"
)

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

required_functions=(
    "rpi-sysinfo"
    "wh_send_payload"
)

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

# Wormhole functions
function log() {
    local message=$(cat -)
    local current_time
    local sleep_time_sec=$(echo "scale=3; $min_time_between_logs_ms / 1000" | bc -q)
    if [ -n "$message" ]; then
        echo "$message" | tee -a "$install_log_path"
        current_time=$(date +%s%N)
        if [ -f "$last_log_time_file" ]; then
            local last_log_time=$(cat "$last_log_time_file")
            local time_diff_ms=$(( (current_time - last_log_time) / 1000000 ))
            if [ "$time_diff_ms" -lt "$min_time_between_logs_ms" ]; then
                sleep "$sleep_time_sec"
            fi
        fi
        ${WH_PATH}/installer/report_install_progress.sh "${install_log_endpoint}" "${WH_INSTALL_ID}" "${message}"
        echo "$current_time" > "$last_log_time_file"
    fi
}

function remap_value() {
    local value=$1
    local in_min=$2
    local in_max=$3
    local out_min=$4
    local out_max=$5
    local clamp=false
    if (( $# < 5 || $# > 6 )); then
        echo "Usage: remap_value <value> <in_min> <in_max> <out_min> <out_max> [-c]" >&2
        return 1
    fi
    if [[ "$6" == "-c" ]]; then
        clamp=true
    elif [[ -n "$6" ]]; then
        echo "Error: The 6th argument must be '-c' or not provided." >&2
        echo "Usage: remap_value <value> <in_min> <in_max> <out_min> <out_max> [-c]" >&2
        return 1
    fi
    local result=$(awk -v val="$value" \
                       -v in_min="$in_min" \
                       -v in_max="$in_max" \
                       -v out_min="$out_min" \
                       -v out_max="$out_max" \
                       -v clamp="$clamp" '
    BEGIN {
        remap = ((val - in_min) * (out_max - out_min) / (in_max - in_min)) + out_min;
        if (clamp == "true") {
            if (remap < out_min) {
                remap = out_min;
            }
            if (remap > out_max) {
                remap = out_max;
            }
        }
        printf "%.2f\n", remap;
    }')
    echo "$result"
}

function log_progress_percent() {
    local progress_percent="$1"
    echo "${marker_progress}${progress_percent}${marker_close}" | log
}

function log_progress_state() {
    local progress_state="$1"
    echo "${marker_state}${progress_state}${marker_close}" | log
}

function get_install_progress() {
    local stage_progress="$1"
    local min_stage_progress="$2"
    local max_stage_progress="$3"
    local stage="$4"
    local total_stages="$5"
    if ! [[ "$stage_progress" =~ ^[[:space:]]*[0-9.]+[[:space:]]*$ ]] || \
       ! [[ "$min_stage_progress" =~ ^[[:space:]]*[0-9.]+[[:space:]]*$ ]] || \
       ! [[ "$max_stage_progress" =~ ^[[:space:]]*[0-9.]+[[:space:]]*$ ]] || \
       ! [[ "$stage" =~ ^[[:space:]]*[0-9.]+[[:space:]]*$ ]] || \
       ! [[ "$total_stages" =~ ^[[:space:]]*[0-9.]+[[:space:]]*$ ]]; then
        echo "Error: All inputs must be numeric." >&2
        return 1
    fi
    if (( total_stages == 0 )) || (( $(echo "$max_stage_progress - $min_stage_progress" | bc) == 0 )); then
        echo "Error: total_stages cannot be zero and max_stage_progress cannot equal min_stage_progress." >&2
        return 1
    fi
    LC_NUMERIC="C" # Set locale for bc and printf compatibility
    total_stages=$((total_stages + 1))
    local progress_calculation=$(bc -l <<< "scale=4; \
        ( ($stage / $total_stages) + \
        ( ($stage_progress - $min_stage_progress) / ($max_stage_progress - $min_stage_progress) / $total_stages) ) * 100.0")
    printf "%.3f\n" "$(echo "$progress_calculation" | cut -d'.' -f1-2)"
}

# The function to detect progress numbers in a given line.
# It looks for patterns like [x/y] or [x]. If a total is available, it outputs two numbers. If not, it outputs only one.
function parse_progress() {
    local line="$1"
    # Try to extract the two-number pattern first
    result=$(echo "$line" | sed -nE 's/.*\[([0-9.]+)\/([0-9.]+)\](.*)$/\1 \2/p')
    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi
    # If that fails, try the single-number pattern
    result=$(echo "$line" | sed -nE 's/.*\[([0-9.]+)\](.*)$/\1/p')
    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi
    return 1
}

function move_on_to_stage() {
    local new_stage="$1"
    echo "${marker_progress}$(get_install_progress 0 0 1 ${new_stage} ${number_of_stages})${marker_close}" | log
    echo "[${wh_prefix}] Finished stage ${install_stage}. Moving to stage ${new_stage}" | log 
    echo "$new_stage" | tee "$checkpoint_stage" >/dev/null
    echo "Rebooting $(hostname) in ${stage_reboot_wait} seconds..." | log
    sleep "${stage_reboot_wait}"
    log_progress_state "Stage ${install_stage} / Rebooting"
    echo "Rebooting $(hostname) now..." | log
    shutdown -r now
}

function auth_request(){
    local url="$1"
    local max_timeout=10
    response=$(curl -s -w "\n%{http_code}" --max-time ${max_timeout} -X GET ${url} -H "Authorization: Bearer ${WH_HARDWARE_API_KEY}")
    http_code=$(echo "$response" | tail -n1) # Extract the last line for the status code
    data=$(echo "$response" | sed '$d') # Remove the last line to get the data
    if [[ "$http_code" == "200" ]]; then
        echo $data
    else
        echo "$Error: ${http_code} - Response body: ${data}"
        exit 1
    fi
}

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
    else
        export "$var"
    fi
done
# Loop through the functions and check if they are defined
for func in "${required_functions[@]}"; do
    if ! type -t "$func" >/dev/null; then
        initialization_errors+="Missing function: $func\n"
        error_occurred=true
    else
        export -f "$func"
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

# Prevent debconf messages
export DEBIAN_FRONTEND=noninteractive

# Constant variables
installer_name="wormholeinstalld"
library_dir="/etc/profile.d"
systemd_service_dir="/etc/systemd/system"
last_log_time_file="/tmp/wormhole_last_log_time.tmp"
min_time_between_logs_ms=200
number_of_stages=6
wh_prefix="WH"
stage_reboot_wait=10 # seconds
error_reboot_time=5 # minutes
marker_fin="___ FINISHED ___"
marker_progress="___ PROGRESS ___"
marker_state="___ STATE ___"
marker_close="___"

# Other variables
install_log_path="${WH_HOME}/wormhole_install.log"
third_party_scripts_dir="${WH_PATH}/third_party"
get_pollrate_endpoint="${WH_SERVER_API_URL}/wh/get_pollrate_rpi"
install_log_endpoint="${WH_SERVER_API_URL}/wh/install_log_write"
check_config_endpoint="${WH_SERVER_API_URL}/wh/rpi.check_config"
checkpoint_boot="${WH_HOME}/.checkpoint-boot"
checkpoint_stage="${WH_HOME}/.checkpoint-stage"
firstrun_log_path="/boot/firstrun.log"
firstrun_backup="/home/firstrun_backup.sh"

# Installation progress tracking
boot_number=2
install_stage=0
install_progress=0

# Recover or create checkpoints
if [ -f "$checkpoint_boot" ]; then
    boot_number=$(<"$checkpoint_boot")
    boot_number=$((boot_number + 1))
    echo "$boot_number" > "$checkpoint_boot"
else
    echo "$boot_number" > "$checkpoint_boot"
fi
if [ -f "$checkpoint_stage" ]; then
    install_stage=$(<"$checkpoint_stage")
else
    echo "$install_stage" > "$checkpoint_stage"
fi

message="[${wh_prefix}] Running Stage #${install_stage}, Boot #${boot_number}"
sdreport "$message"

# Boot 2 is the first boot after firstboot
if [ $boot_number -eq 2 ]; then
    # Packages required for log function to work
    echo "${marker_state}Installing dependencies${marker_close}" | tee -a "${install_log_path}"
    echo "$message" | tee -a "${install_log_path}"
    echo "[${wh_prefix}] Checking bash version" | tee -a "${install_log_path}"
    bash --version | tee -a "${install_log_path}"
    echo "[${wh_prefix}] Installing dependencies for the installer: ${package_list_dependency}" | tee -a "${install_log_path}"
    apt-get install -y ${package_list_dependency} | while read -r line; do
        echo "$line" >> "${install_log_path}"
    done
    # Catch the server up to logs from previous boot
    log_progress_state "Checking firstrun log"
    cat "${install_log_path}" | while read -r line; do
        echo "$line" | log
        script_progress=$(parse_progress "$line")
        if [ $? -eq 0 ]; then
            stage_progress=$(remap_value $(echo "$script_progress" | cut -d ' ' -f 1) 1 $(echo "$script_progress" | cut -d ' ' -f 2) 0 1)
            log_progress_percent "$(get_install_progress "${stage_progress}" "0" "1" "${install_stage}" "${number_of_stages}")"
        fi
    done
    # Remove firstrun.sh log and firstrun.sh backup
    rm -f "$firstrun_log_path" "$firstrun_backup"
    # Real-time logging can start now
    log_progress_state "Stage ${install_stage} / Starting the installation"
    echo "0" | log
    echo "1." | log
    echo "2.." | log
    echo "3..." | log
    echo "4...." | log
    echo "5....." | log
    echo "Hello ${WH_INSTALL_USER}!" | log
    echo "This is ${installer_name} from your $(hostname)" | log
    echo "Raspberry Pi will reboot multiple times during installation. Setting boot priority to the current boot media." | log
    ${WH_PATH}/set_boot_order.sh -current | log
else
    log_progress_state "Starting up"
    echo "$message" | log
fi

rpi-sysinfo | while read -r line; do
    echo "[rpi-sysinfo] $line" | log
done

# Init preflight check status
preflight_checks_passed=true
preflight_errors=""

# Check current IP address
echo "[${wh_prefix}] Checking IP address.." | log
my_ip=$(nmcli -t -f IP4.ADDRESS device show | head -1 | cut -d"/" -f1 | cut -d : -f2)
if [[ $my_ip == $WH_IP_ADDR ]]; then
    echo "[${wh_prefix}] IP address ${my_ip} issued by the router's DHCP is matching the configuration." | log
else
    preflight_checks_passed=false
    preflight_errors="${preflight_errors}IP address configuration mismatch;"
    echo "[${wh_prefix}] IP address issued by the router's DHCP ${my_ip} does not match the configuration - ${WH_IP_ADDR}" | log
    echo "[${wh_prefix}] Please reconfigure the DHCP or change the Wormhole's configured IP address and reboot the Raspberry Pi." | log
fi

# Wait until configuration is available to the server
echo "[${wh_prefix}] Getting authenticated by the server..." | log
payload=$(jq --null-input \
            --arg topic "check" \
            '{topic: $topic}')
wh_send_payload "$payload" "$check_config_endpoint" | log
if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    echo "[${wh_prefix}] Hardware API key recognized by the server." | log
else
    preflight_checks_passed=false
    preflight_errors="${preflight_errors}Failed to authenticate with the server;"
    echo "[${wh_prefix}] Device's hardware API key not recognized my the server yet. Waiting for configuration to be uploaded by the installer." | log
fi

# Pass checks before installation continues
if [[ $preflight_checks_passed == true ]]; then
    if [[ $install_stage -lt 1 ]]; then
        install_stage=1
    fi
    echo "[${wh_prefix}] Preflight checks passed" | log
else
    echo -e "[${wh_prefix}] Can't continue installation! Errors:\n${preflight_errors}" | log
    log_progress_state "Waiting for errors to be resolved..."
    echo "[${wh_prefix}] Will automatically reboot and retry in ${error_reboot_time} minutes. Reboot manually if ready now." | log
    shutdown -r +${error_reboot_time}
    if [[ -n "$preflight_errors" ]]; then
        sdreport_failure "$preflight_errors"
    else
        sdreport_failure "Can't continue installation"
    fi
fi

# Start the installation. Report current stage
log_progress_state "Stage ${install_stage}"
if [[ $install_stage -eq 0 ]]; then
    echo "[${wh_prefix}] ${installer_name} starting the installation process" | log
else
    echo "[${wh_prefix}] ${installer_name} continuing the installation process: boot ${boot_number}, stage ${install_stage}" | log
fi

# Try to get and set pollrate to match server's
server_pollrate=$(auth_request "$get_pollrate_endpoint")
if [ $? -eq 0 ]; then
    min_time_between_logs_ms=$server_pollrate
    echo "[${wh_prefix}] Setting pollrate to server's ${min_time_between_logs_ms} ms." | log
else
    echo "[${wh_prefix}] Failed to get server's pollrate - setting to ${min_time_between_logs_ms} ms." | log
fi

case $install_stage in
    1)  log_progress_state "Stage ${install_stage} / Updating the OS"
        # apt-upgrade progress tracking
        declare -i total_packages=0
        declare -i total_tasks=0
        declare -i current_task=0
        ${WH_PATH}/installer/initial_update.sh | while read -r line; do
            echo "$line" | log
            if [[ $total_packages -eq 0 ]]; then # Get the total number of packages and calculate total tasks.
                if echo "$line" | grep -qP '\d+ upgraded, \d+ newly installed, \d+ to remove'; then
                    upgraded_packages=$(echo "$line" | grep -oP '\d+(?= upgraded)')
                    newly_installed=$(echo "$line" | grep -oP '\d+(?= newly installed)')
                    to_remove=$(echo "$line" | grep -oP '\d+(?= to remove)')
                    total_packages=$((upgraded_packages + newly_installed + to_remove))
                    total_tasks=$((total_packages * 3))
                    echo "[${wh_prefix}] Total tasks (upgrade ${upgraded_packages} + install ${newly_installed} + remove ${to_remove}): $total_packages" | log
                fi
            fi
            if [[ $total_tasks -gt 0 ]]; then
                if [[ "$line" =~ Get:([0-9]+) ]]; then # Check for the downloading phase (Get:N).
                    current_task="${BASH_REMATCH[1]}"
                    log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
                elif [[ "$line" =~ Preparing\ to\ unpack ]]; then # Check for the unpacking/installing phase.
                    current_task=$((current_task + 1))
                    log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
                elif [[ "$line" =~ Setting\ up\  ]]; then # Check for the setting up phase.
                    current_task=$((current_task + 1))
                    log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
                fi
            fi
        done
        move_on_to_stage "2"
        ;;
    2)
        stage_progress=0.0
        stage_max_progress=4.0
        log_progress_state "Stage ${install_stage} / Installing git"
        ${WH_PATH}/installer/git_install.sh --lfs | while read -r line; do
            echo "$line" | log
            script_progress=$(parse_progress "$line")
            if [ $? -eq 0 ]; then
                stage_progress=$(remap_value $(echo "$script_progress" | cut -d ' ' -f 1) 0 $(echo "$script_progress" | cut -d ' ' -f 2) 0 1)
                log_progress_percent "$(get_install_progress "${stage_progress}" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
            fi
        done
        log_progress_state "Stage ${install_stage} / Installing docker"
        ${WH_PATH}/installer/docker_install.sh | while read -r line; do
            echo "$line" | log
            script_progress=$(parse_progress "$line")
            if [ $? -eq 0 ]; then
                stage_progress=$(remap_value $(echo "$script_progress" | cut -d ' ' -f 1) 0 $(echo "$script_progress" | cut -d ' ' -f 2) 1 4)
                log_progress_percent "$(get_install_progress "${stage_progress}" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
            fi
        done
        move_on_to_stage "3"
        ;;
    3)  
        # Stage progress tracking
        declare -i total_packages=0
        declare -i current_task=0
        total_tasks=0
        first_part_progress=2 # How much total progress is relative to first part's progress
        number_of_repositories=${#repositories_to_clone[@]}
        number_of_third_party_scripts=${#third_party_scripts[@]}
        log_progress_state "Stage ${install_stage} / Installing additional packages"
        echo "[${wh_prefix}] This stage will install packages:" | log
        to_install=($package_list_additional)
        for item in "${to_install[@]}"; do
            echo "[${wh_prefix}] - $item" | log
            apt list $item | log
        done
        sudo apt-get install -y ${package_list_additional} | while read -r line; do
            echo "$line" | log
            if [[ $total_packages -eq 0 ]]; then # Get the total number of packages and calculate total tasks.
                if echo "$line" | grep -qP '\d+ upgraded, \d+ newly installed, \d+ to remove'; then
                    upgraded_packages=$(echo "$line" | grep -oP '\d+(?= upgraded)')
                    newly_installed=$(echo "$line" | grep -oP '\d+(?= newly installed)')
                    to_remove=$(echo "$line" | grep -oP '\d+(?= to remove)')
                    total_packages=$((upgraded_packages + newly_installed + to_remove))
                    echo "[${wh_prefix}] Total tasks (upgrade ${upgraded_packages} + install ${newly_installed} + remove ${to_remove}): $total_packages" | log
                    total_tasks=$(echo "($total_tasks + ($total_packages * 3)) * $first_part_progress" | bc)
                fi
            fi
            if [[ $total_tasks -gt 0 ]]; then
                if [[ "$line" =~ Get:([0-9]+) ]]; then # Check for the downloading phase (Get:N).
                    current_task="${BASH_REMATCH[1]}"
                    log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
                elif [[ "$line" =~ Preparing\ to\ unpack ]]; then # Check for the unpacking/installing phase.
                    current_task=$((current_task + 1))
                    log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
                elif [[ "$line" =~ Setting\ up\  ]]; then # Check for the setting up phase.
                    current_task=$((current_task + 1))
                    log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
                fi
            fi
        done
        current_task=$((number_of_repositories + number_of_third_party_scripts))
        total_tasks=$(echo "$current_task * $first_part_progress" | bc)
        log_progress_state "Stage ${install_stage} / Cloning git repositories"
        for repo_url in "${repositories_to_clone[@]}"; do
            repo_name=$(basename ${repo_url} | sed 's/\.git$//')
            repo_desination="${WH_PATH}/repos/${repo_name}"
            echo "[${wh_prefix}] Cloning ${repo_name} into ${repo_desination}" | log
            ${WH_PATH}/installer/git_clone_repo.sh "${repo_url}" "${repo_desination}" | while read -r line; do
                echo "$line" | log
            done
            current_task=$((current_task + 1))
            log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
        done
        log_progress_state "Stage ${install_stage} / Downloading third-party scripts"
        for script_url in "${third_party_scripts[@]}"; do
            script_file=$(basename ${script_url})
            script_name=$(echo ${script_file} | sed 's/\.sh$//')
            script_desination="${third_party_scripts_dir}/${script_name}/${script_file}"
            echo "[${wh_prefix}] Downloading ${script_name} into ${script_desination}" | log
            mkdir -p "${third_party_scripts_dir}/${script_name}"
            wget --output-document="${script_desination}" "${script_url}" | while read -r line; do
                echo "$line" | log
            done
            chmod +x "$script_desination"
            current_task=$((current_task + 1))
            log_progress_percent "$(get_install_progress "${current_task}" "1" "${total_tasks}" "${install_stage}" "${number_of_stages}")"
        done
        move_on_to_stage "4"
        ;;
    4)
        stage_progress=0.0
        stage_max_progress=3.0
        ${WH_PATH}/wormhole.sh --version | log
        log_progress_state "Stage ${install_stage} / Updating docker configs"
        log_progress_percent "$(get_install_progress "${stage_progress}" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
        ${WH_PATH}/wormhole.sh docker update 2>&1 | while read -r line; do
            echo "$line" | log
        done
        stage_progress=1.0
        log_progress_state "Stage ${install_stage} / Pulling docker images"
        log_progress_percent "$(get_install_progress "${stage_progress}" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
        ${WH_PATH}/wormhole.sh docker stack pull 2>&1 | while read -r line; do
            if ! echo "$line" | grep -q " Extracting \| Downloading \| Waiting"; then
                echo "$line" | log
            fi
        done
        stage_progress=2.0
        log_progress_state "Stage ${install_stage} / Starting up docker stacks"
        log_progress_percent "$(get_install_progress "${stage_progress}" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
        ${WH_PATH}/wormhole.sh docker stack up 2>&1 | while read -r line; do
            echo "$line" | log
        done
        move_on_to_stage "5"
        ;;
    5)
        stage_progress=0.0
        stage_max_progress=4.0
        log_progress_state "Stage ${install_stage} / Checking filesystem"
        ${WH_PATH}/migration.sh | while read -r line; do
            echo "$line" | log
            script_progress=$(parse_progress "$line")
            if [ $? -eq 0 ]; then
                stage_progress=$(remap_value $(echo "$script_progress" | cut -d ' ' -f 1) 0 $(echo "$script_progress" | cut -d ' ' -f 2) 0 3)
                log_progress_percent "$(get_install_progress "${stage_progress}" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
            fi
        done
        move_on_to_stage "6"
        ;;
    $number_of_stages)
        stage_max_progress=2.0
        sdreport "Intallation finished. Performing final steps"
        echo "Intallation finished. Performing final steps" | log
        log_progress_percent "$(get_install_progress "1" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
        ${WH_PATH}/benchmark.sh | log
        echo "Disabling ${installer_name} and removing checkpoint files" | log
        systemctl disable ${installer_name}.service | log
        rm -f "${checkpoint_boot}" | log
        rm -f "${checkpoint_stage}" | log 
        log_progress_percent "$(get_install_progress "2" "0" "${stage_max_progress}" "${install_stage}" "${number_of_stages}")"
        echo "$marker_fin" | log
        sdreport_success "Finished"
        ;;
    *)
        echo "Error: Unknown checkpoint value in $checkpoint_stage. Exiting." | log
        sdreport_failure "Error: Unknown checkpoint value in $checkpoint_stage. Exiting."
        ;;
esac