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
    --version|-v|-V|--v|--V)
        echo $version
        exit 0
        ;;
    --help|-h|--h)
        show_help
        exit 0
        ;;
    update)
        ${base_dir}/update.sh
        exit 0
        ;;
    migrate)
        ${base_dir}/migration.sh
        exit 0
        ;;
    check-migration-plans)
        check_migration_plans
        ;;
    docker)
        shift
        docker_command="$1"
        if [[ $docker_command == 'update' ]]; then
            ${base_dir}/docker_update_config.sh
            [ $? -ne 0 ] && exit 1
            ${base_dir}/docker_update_env.sh
        elif [[ $docker_command == 'update-env' ]]; then
            ${base_dir}/docker_update_env.sh
        elif [[ $docker_command == 'stack' ]]; then
            shift
            if [[ $1 == "mounts" ]]; then
                ${base_dir}/docker_manage.sh $@ | sort -u
            else
                ${base_dir}/docker_manage.sh $@
            fi
        elif [[ $docker_command == 'backup' ]]; then
            shift
            ${base_dir}/docker_manage.sh stop $@
            ${base_dir}/docker_backups.sh backup $@
            ${base_dir}/docker_manage.sh start $@
        elif [[ $docker_command == 'full-restore' ]]; then
            shift
            ${base_dir}/docker_manage.sh down $@
            ${base_dir}/docker_manage.sh create $@
            ${base_dir}/docker_backups.sh restore $@
            ${base_dir}/docker_manage.sh start $@
        elif [[ $docker_command == 'restore' ]]; then
            shift
            ${base_dir}/docker_manage.sh stop $@
            ${base_dir}/docker_backups.sh restore $@
            ${base_dir}/docker_manage.sh start $@
        else
            echo "docker what?"
            echo "Usage: $0 <update update-env stack>"
            exit 0
        fi
        ;;
    config)
        ${base_dir}/config_update.sh "$2" "$3"
        ;;
    *)
        echo "Unknown command $command"
        show_help
        exit 1
        ;;
esac
