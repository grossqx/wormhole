#!/bin/bash


## Text colors:
source ${base_dir}/res/theme.env


validate_config_file() {
    local CONFIG_PATH=$1

    # Define the list of required variables to check for.
    # This makes the check easy to update.
    required_variables=(
        "RPI_CONFIG_NAME"
        "RPI_HOSTNAME"
        "RPI_DESCRIPTION"
        "RPI_CONFIG_TAG"
        "RPI_CONFIG_SEARCH"
        "RPI_TIMEZONE"
        "RPI_IP_ADDR"
        "RPI_DOMAIN"
        "RPI_WH_PORT"
    )

    echo "File found. Checking for required variables..."
    source "${CONFIG_PATH}"

    failed=0

    for var in "${required_variables[@]}"; do
        if ! grep -q "^$var=" "$CONFIG_PATH"; then
            echo "Error: Required variable '$var' not found in '$CONFIG_PATH'." >&2
            failed=1
        fi
    done

    if ! [[ "$RPI_HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        echo -e "${T_RED}Error: Invalid hostname '${RPI_HOSTNAME}'. It should only contain alphanumeric characters and hyphens.${T_NC}" >&2
        failed=1
    fi

    if ! [[ "$RPI_TIMEZONE" =~ ^[a-zA-Z/]+$ ]]; then
        echo -e "${T_RED}Error: Invalid timezone '${RPI_TIMEZONE}'. It must be a valid TZ identifier, like in https://en.wikipedia.org/wiki/List_of_tz_database_time_zones ${T_NC}" >&2
        failed=1
    fi
    
    if [[ ! "$RPI_HARDWARE_API_KEY" =~ ^[a-fA-F0-9]+$ ]]; then
        echo -e "${T_RED}Error: Invalid hardware API key '${RPI_HARDWARE_API_KEY}'. It should only contain hexadecimal characters.${T_NC}" >&2
        failed=1
    fi

    if [[ ! -z "$RPI_IP_ADDR" ]]; then
        if ! [[ "$RPI_IP_ADDR" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])$ ]]; then
            echo -e "${T_RED}Error: Invalid IP address '${RPI_IP_ADDR}'. It should be in the format xxx.xxx.xxx.xxx.${T_NC}" >&2
            failed=1
        fi
    else
        echo -e "${T_YELLOW}Warning: No static IP address provided by the configuration. It will have to be set up later.${T_NC}"
    fi

    if [[ ! -z "$RPI_DOMAIN" ]]; then
        if ! [[ "$RPI_DOMAIN" =~ ^(https://|http://) ]]; then
            echo -e "${T_RED}Error: Invalid domain '${RPI_DOMAIN}'. It should start with 'https://' or 'http://'.${T_NC}" >&2
            failed=1
        fi
        if [[ "$RPI_DOMAIN" =~ /$ ]]; then
            echo -e "${T_RED}Error: Invalid domain '${RPI_DOMAIN}'. Trailing slash is not allowed.${T_NC}" >&2
            failed=1
        fi
    else
        echo -e "${T_YELLOW}Warning: No domain name provided. Either a static public IP or a domain name is required for incoming connections.${T_NC}"
    fi

    if ! [[ "$RPI_WH_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${T_RED}Error: Invalid WH port number '${RPI_WH_PORT}'. It should be a positive integer.${T_NC}" >&2
        failed=1
    fi
    
    if [[ ! -z "$RPI_WIFI_LOC" ]]; then
        if [[ ! "$RPI_WIFI_LOC" =~ ^[a-zA-Z]{2}$ ]]; then
            echo -e "${T_RED}Error: Invalid wifi location '${RPI_WIFI_LOC}'. It should be a two letter code, ISO 3166-1 alpha-2.${T_NC}" >&2
            failed=1
        fi
    fi

    if [[ ! -z "$RPI_WIFI_ENCRYPTED" ]]; then
        if [[ "$RPI_WIFI_ENCRYPTED" != "true" && "$RPI_WIFI_ENCRYPTED" != "false" ]]; then
            echo -e "${T_RED}Error: Invalid wifi encryption setting '${RPI_WIFI_ENCRYPTED}'. It should be either 'true' or 'false'.${T_NC}" >&2
            failed=1
        fi
    fi

    if [[ ! -z "$RPI_SSH_ENCRYPTED" ]]; then
        if [[ "$RPI_SSH_ENCRYPTED" != "true" && "$RPI_SSH_ENCRYPTED" != "false" ]]; then
            echo -e "${T_RED}Error: Invalid SSH encryption setting '${RPI_SSH_ENCRYPTED}'. It should be either 'true' or 'false'.${T_NC}" >&2
            failed=1
        fi
    fi

    if [[ ! -z "$RPI_SSH_USER" ]]; then
        if ! [[ "$RPI_SSH_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo -e "${T_RED}Error: Invalid SSH user name '${RPI_SSH_USER}'. It should only contain alphanumeric characters and underscores.${T_NC}" >&2
            failed=1
        fi
    fi

    if [[ ! -z "$RPI_SSH_PORT" ]]; then
        if ! [[ "$RPI_SSH_PORT" =~ ^[0-9]+$ ]]; then
            echo -e "${T_RED}Error: Invalid SSH port number '${RPI_WH_PORT}'. It should be a positive integer.${T_NC}" >&2
            failed=1
        fi
    fi

    if [[ $failed -eq 1 ]]; then
        echo -e "${T_RED}Configuration is faulty.${T_NC}"
        return 1
    fi
    echo -e "${T_GREEN}Validation success! All required variables are present in '$CONFIG_PATH'.${T_NC}"
    return 0
}

validate_config_file $1