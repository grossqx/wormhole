#!/bin/bash

echo "Fetching environment variables from ${docker_dir}/environment.sh"

if [ -f "${docker_dir}/environment.sh" ]; then
    source "${docker_dir}/environment.sh"
else
    echo "Warning: No environment file not found at ${docker_dir}/environment.sh"
fi

export docker_dir
export docker_stacks
export docker_configs
export docker_volumes

echo "Scanning for required variables per-stack in $docker_stacks"
if [ ! -d "$docker_stacks" ]; then
    echo "Error: Docker stacks directory '$docker_stacks' is absent."
    exit 1
fi

STACK_LIST=$(ls "${docker_stacks}")
if [ -z "$STACK_LIST" ]; then
    echo "Warning: No stack directories found in ${docker_stacks}"
fi

MISSING_VARS_LOG=$(mktemp)
find "$docker_stacks" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' stack_dir; do
    STACK_NAME=$(basename "$stack_dir")
    ENV_FILE="${stack_dir}/.env"
    echo "$STACK_NAME stack:"
    for sh_file in "$stack_dir"/*.sh; do
        if [ -f "$sh_file" ]; then
            echo " - Running setup script ${stack_dir}/$(basename "$sh_file")"
            (source "$sh_file") 2>&1 | sed 's/^/   > /'
        fi
    done
    REQUIRED_VARS_RAW=$(grep -oE '\$\{[a-zA-Z0-9_]+\}' "$stack_dir"/*.y{ml,aml} 2>/dev/null)
    if [ -z "$REQUIRED_VARS_RAW" ]; then
        echo " - No environment variables (e.g., \${VAR}) found in compose files for $STACK_NAME."
        continue
    fi
    REQUIRED_VARS=($(echo "$REQUIRED_VARS_RAW" | cut -d ':' -f 2 | tr -d '${}' | sort -u))
    printf " - %d required variables: " "${#REQUIRED_VARS[@]}"
    printf "%s " "${REQUIRED_VARS[@]}"
    printf "\n"
    MISSING_VARS=()
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            MISSING_VARS+=("$var")
        fi
    done
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        printf "Error: Missing Environment Variables for %s: " "$STACK_NAME"
        printf "%s " "${MISSING_VARS[@]}"
        printf "\n"
        printf "%s\n" "${MISSING_VARS[@]}" >> "$MISSING_VARS_LOG"
        continue
    fi
    > "$ENV_FILE"
    echo " - All required variables are set."
    for var in "${REQUIRED_VARS[@]}"; do
        printf "%s=%s\n" "$var" "${!var}" >> "$ENV_FILE"
    done
    echo " - Saved ${#REQUIRED_VARS[@]} environment variables for ${STACK_NAME} in $ENV_FILE"
done

if [ -s "$MISSING_VARS_LOG" ]; then
    mapfile -t missing_vars < "$MISSING_VARS_LOG"
fi
rm "$MISSING_VARS_LOG"

if [ ${#missing_vars[@]} -gt 0 ]; then
    printf "Error: Missing environment Variables: "
    for var in "${missing_vars[@]}"; do
        printf "%s " "${var}"
    done
    printf "\n"
    exit 1
else
    echo "Successfully updated enviromnent for all stacks."
    exit 0
fi