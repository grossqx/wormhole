#!/bin/bash

binary_name="wormhole"
version="placeholder version"

command="$1"

# Resolve parent directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
base_dir="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

function show_help(){
    echo "Wormhole ${version}"
    echo
    echo "Usage: ${binary_name} <command> [arguments]"
    echo
    echo "Wormhole Management Utility - A script for maintenance, migration, and Docker stack handling."
    echo
    echo "Primary Commands:"
    echo "  -h, --help                 Show this help message."
    echo "  -v, --version              Show version information."
    echo
    echo "Maintenance & Lifecycle:"
    echo "  -u, update                 Updates the Wormhole manager script itself from the server."
    echo "  -su, system-update         Run a system and service update (runs ${base_dir}/system_update.sh)."
    echo "  -m, migrate                Run the system migration script (runs ${base_dir}/migration.sh)."
    echo "  -cm, check-migration-plans Check for and execute any pending migration order scripts."
    echo "  -c, config <key> <value>   Update a specific ${binary_name} configuration key."
    echo "  -au, auto-update <system|self> <schedule>|disabled  Schedule or disable automatic updates."
    echo "                             Schedule uses 5-field cron format (e.g., \"0 3 * * *\")."
    echo "                             Example: ${binary_name} auto-update system \"0 3 * * *\""
    echo "                             Example: ${binary_name} auto-update self disabled"
    echo
    echo "Docker Stack Management:"
    echo "  -s, stack <command> [stack]  Manage Docker stacks (runs ${base_dir}/docker_manage.sh)."
    echo "                             Note: If [stack] is omitted, the command runs on ALL stacks."
    echo "                             Example: ${binary_name} stack up my_stack"
    echo "                             Command 'mounts' lists unique stack mounts/volumes."
    echo
    echo "Docker Operations (Updates, Backups, Restores):"
    echo "  -d, docker <sub-command> [stack] Perform complex Docker operations."
    echo "    Sub-commands:"
    echo "      -u, update             Update both Docker configurations and environment files."
    echo "      -ue, update-env        Update only the Docker environment file."
    echo "      -b, backup [stack]     Stop, backup data volumes, and restart a specific stack."
    echo "      -r, restore [stack]    Stop, restore data volumes, and restart a specific stack (volume replacement)."
    echo "      -fr, full-restore [stack] Down, recreate, restore volumes, and start a specific stack (full rebuild)."
    echo
}

function run_migration_order(){
    wh_log "Running the migration order ${migration_order}"
    chmod +x ${migration_order}
    ${migration_order} | while read -r line; do
        wh_log "$line" 
    done
    result=${PIPESTATUS[0]}
    if [ $result -ne 0 ]; then
        wh_log "Error: ${migration_order} failed with status $result."
    else
        wh_log "Migration successfull. Removing ${migration_order}"
        rm -f ${migration_order}
        wh_log "Rebooting after migration in 1 minute"
        shutdown -r +1
    fi
}

function check_migration_plans(){
if [ -f ${migration_order} ]; then
    wh_log "New migration order discovered"
    if systemctl is-enabled --quiet ${install_service_name}.service; then
        wh_log "${install_service_name} is still enabled. Delaying migration until installation is finished."
    else
        run_migration_order
    fi
else
    wh_log "No migration orders to execute"
fi
}

function manage_auto_update() {
    local update_type="$1"
    local schedule="$2"
    local cron_file="/etc/cron.d/wh-updates"
    local unique_id=""
    local command_to_run=""
    local check_line=""
    if [[ "$update_type" == "system" ]]; then
        unique_id="#WORMHOLE_SYSTEM_UPDATE_CRON#"
        command_to_run="$base_dir/wormhole.sh -su"
    elif [[ "$update_type" == "self" ]]; then
        unique_id="#WORMHOLE_SELF_UPDATE_CRON#"
        command_to_run="$base_dir/wormhole.sh -u"
    else
        wh_log "Error: Unknown update type '$update_type'. Use 'system' or 'self'."
        return 1
    fi
    if [[ "$schedule" == "disabled" ]]; then
        if sudo grep -q "$unique_id" "$cron_file" 2>/dev/null; then
            sudo sed -i "/$unique_id/d" "$cron_file"
            wh_log "Disabled $update_type auto-update. Rule removed from $cron_file."
        else
            wh_log "$update_type auto-update rule not found. Nothing to disable."
        fi
        if [[ -f "$cron_file" ]] && [[ -z "$(sudo egrep -v '(^#|^$)' "$cron_file")" ]]; then
            sudo rm -f "$cron_file"
            wh_log "$cron_file is now empty and has been removed."
        fi
        sudo systemctl restart cron 2>/dev/null
        return 0
    fi
    check_line="$schedule root $command_to_run $unique_id"
    local current_crontab_content=""
    if [[ ! -f "$cron_file" ]]; then
        wh_log "Creating new system cron file: $cron_file"
        sudo touch "$cron_file" && sudo chmod 0644 "$cron_file" && sudo chown root:root "$cron_file"
    else
        current_crontab_content=$(sudo cat "$cron_file" 2>/dev/null | grep -v -F "$unique_id")
    fi
    local temp_file=$(mktemp)
    echo -e "$current_crontab_content\n$check_line" | sudo tee "$temp_file" > /dev/null
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    sudo mv "$temp_file" "$cron_file"
    wh_log "Attempting to install cron rule and validate syntax..."
    sudo systemctl restart cron 2>/dev/null 
    sleep 2
    if sudo journalctl -u cron --since "$start_time" --no-pager | grep -qE "ERROR|BAD.*wh-updates|Syntax error"; then
        wh_log "Error: The schedule '$schedule' has a syntax error. Reverting."
        sudo sed -i "/$unique_id/d" "$cron_file"
        if [[ -f "$cron_file" ]] && [[ -z "$(sudo egrep -v '(^#|^$)' "$cron_file")" ]]; then
            sudo rm -f "$cron_file"
            wh_log "$cron_file is now empty and has been removed."
        fi
        sudo systemctl restart cron 2>/dev/null
        return 1
    fi
    wh_log "Successfully set $update_type auto-update to schedule: '$schedule'"
    wh_log "Cron command: $command_to_run"
    return 0
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
# Loop through the variables and check if they are set and not empty, then export them
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        initialization_errors+="Missing variable: $var\n"
        error_occurred=true
    else
        export "$var"
    fi
done
# Loop through the functions and check if they are defined, then export them
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
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo or as root."
   exit 1
fi

docker_dir="${base_dir}/docker"
docker_configs="${docker_dir}/configs" && mkdir -p "${docker_configs}"
docker_stacks="${docker_dir}/stacks" && mkdir -p "${docker_stacks}"
docker_volumes="${WH_HOME}/docker_storage" && mkdir -p "${docker_volumes}"
backup_dir="${WH_HOME}/backups" && mkdir -p "${backup_dir}"
migration_order="${WH_HOME}/migration_order.sh"
install_service_name="wormholeinstalld"

export base_dir
export docker_dir
export docker_configs
export docker_stacks
export docker_volumes
export backup_dir
export -f wh-backup
export -f wh-restore
export -f wh-generate-backup-basename
export -f wh-get-latest-backup

case $command in
    --version|-v|-V|--v|--V|version)
        echo $version
        exit 0
        ;;
    --help|-h|--h|help)
        show_help
        exit 0
        ;;
    -u|update)
        wh_log "Starting wormhole update..."
        ${base_dir}/update.sh
        wh_log "Completed wormhole update. exit status: $?"
        exit 0
        ;;
    -su|system-update)
        wh_log "Starting system update..."
        ${base_dir}/system_update.sh 2>&1| while read -r line; do
            wh_log "$line"
        done
        wh_log "Completed system update. exit status: ${PIPESTATUS[0]}"
        exit 0
        ;;
    -m|migrate)
        ${base_dir}/migration.sh
        exit 0
        ;;
    -cm|check-migration-plans)
        check_migration_plans
        ;;
    -s|stack)
        shift
        if [[ $1 == "mounts" ]]; then
            ${base_dir}/docker_manage.sh $@ | sort -u
        else
            ${base_dir}/docker_manage.sh $@
        fi
        ;;
    -d|docker)
        shift
        docker_command="$1"
        case "$docker_command" in
            -u|update)
                wh_log "Starting docker configuration update..."
                ${base_dir}/docker_update_config.sh || exit 1
                wh_log "Updating docker environment..."
                ${base_dir}/docker_update_env.sh || exit 1
                wh_log "Completed docker configuration update"
                ;;
            -ue|update-env)
                wh_log "Starting docker environment update..."
                ${base_dir}/docker_update_env.sh || exit 1
                wh_log "Completed docker environment update"
                ;;
            -b|backup)
                shift
                wh_log "Starting docker backup..."
                ${base_dir}/docker_manage.sh stop $@ || exit 1
                wh_log "Backing up container volumes..."
                ${base_dir}/docker_backups.sh backup $@ || exit 1
                wh_log "Restarting containers..."
                ${base_dir}/docker_manage.sh start $@ || exit 1
                wh_log "Completed docker backup"
                ;;
            -fr|full-restore)
                shift
                wh_log "Starting full-restore process..."
                ${base_dir}/docker_manage.sh down $@ || exit 1
                wh_log "Creating containers for services..."
                ${base_dir}/docker_manage.sh create $@ || exit 1
                wh_log "Restoring container volumes..."
                ${base_dir}/docker_backups.sh restore $@ || exit 1
                wh_log "Starting docker containers..."
                ${base_dir}/docker_manage.sh start $@ || exit 1
                wh_log "Completed full-restore process"
                ;;
            -r|restore)
                shift
                wh_log "Starting docker restore process..."
                ${base_dir}/docker_manage.sh stop $@ || exit 1
                wh_log "Restoring container volumes..."
                ${base_dir}/docker_backups.sh restore $@ || exit 1
                wh_log "Restarting containers..."
                ${base_dir}/docker_manage.sh start $@ || exit 1
                wh_log "Completed docker restore process"
                ;;
            *)
                echo "docker what?"
                echo "Usage: $0 docker [-u|-ue|-b|-r|-fr] [stack_name]"
                exit 1
                ;;
        esac
        ;;
    -c|config)
        ${base_dir}/config_update.sh "$2" "$3"
        [ $? -ne 0 ] && exit 1
        wh_log "Configuration variable $2 was updated."
        ;;
    -au|auto-update)
        shift
        type="$1"
        time_spec="$2"
        if [[ -z "$type" || -z "$time_spec" ]]; then
            echo "Usage: $0 auto-update <system|self> \"<cron_schedule>\"|disabled"
            exit 1
        fi
        manage_auto_update "$type" "$time_spec" || exit 1
        wh_log "Auto-update for $type was set to '$time_spec'"
        exit 0
        ;;
    *)
        echo "Unknown command $command"
        show_help
        exit 1
        ;;
esac
