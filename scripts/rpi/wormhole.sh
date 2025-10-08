#!/bin/bash

function show_help(){
    echo "Wormhole ${version}"
}

command="$1"

version="placeholder version"

# Resolve parent directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
base_dir="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

binary_name="wormhole"

# Files to be sourced
dependencies=(
    "/etc/environment"
    "/etc/profile.d/get_rpi_sysinfo.sh"
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
    "get_rpi_sysinfo"
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

docker_configs="${base_dir}/docker"
docker_volumes="${WH_HOME}/docker_storage"

export docker_configs
export docker_volumes

mkdir -p "${docker_configs}"
mkdir -p "${docker_volumes}"

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
        sudo -E ${base_dir}/update.sh
        exit 0
        ;;
    docker)
        shift
        docker_command="$1"
        if [[ $docker_command == 'update' ]]; then
            sudo -E ${base_dir}/docker_update_config.sh
            sudo -E ${base_dir}/docker_update_env.sh
        elif [[ $docker_command == 'update-env' ]]; then
            sudo -E ${base_dir}/docker_update_env.sh
        elif [[ $docker_command == 'stack' ]]; then
            shift
            sudo -E ${base_dir}/docker_manage.sh $@
        else
            echo "docker what?"
            exit 0
        fi
        ;;
    config-update)
        ${base_dir}/config_update.sh "$2" "$3"
        ;;
    *)
        echo "Unknown command $command"
        exit 1
        ;;
esac