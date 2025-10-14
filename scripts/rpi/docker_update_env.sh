#!/bin/bash

PREFIX="[docker update env] "

echo "Fetching environment variables"

source ${docker_dir}/environment.sh
export docker_dir
export docker_configs
export docker_volumes

echo "Scanning for required variables per-stack in $STACKS_DIR"

MISSING_VARS_LOG=$(mktemp)
find "$STACKS_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' stack_dir; do
    STACK_NAME=$(basename "$stack_dir")
    ENV_FILE="${stack_dir}/.env"
    echo "${PREFIX}Processing stack: $STACK_NAME"
    for sh_file in "$stack_dir"/*.sh; do
        if [ -f "$sh_file" ]; then
            echo "${PREFIX}Sourcing setup script: $(basename "$sh_file")"
            source "$sh_file"
        fi
    done
    REQUIRED_VARS_RAW=$(grep -oE '\$\{[a-zA-Z0-9_]+\}' "$stack_dir"/*.y{ml,aml} 2>/dev/null)
    if [ -z "$REQUIRED_VARS_RAW" ]; then
        echo "${PREFIX}No environment variables (e.g., \${VAR}) found in compose files for $STACK_NAME."
        continue
    fi
    REQUIRED_VARS=($(echo "$REQUIRED_VARS_RAW" | cut -d ':' -f 2 | tr -d '${}' | sort -u))
    printf "${PREFIX}Found %d unique variables: " "${#REQUIRED_VARS[@]}"
    printf "%s " "${REQUIRED_VARS[@]}"
    printf "\n"
    MISSING_VARS=()
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            MISSING_VARS+=("$var")
        fi
    done
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        printf "${PREFIX}Error: Missing Environment Variables for %s: " "$STACK_NAME"
        printf "%s " "${MISSING_VARS[@]}"
        printf "\n"
        printf "%s\n" "${MISSING_VARS[@]}" >> "$MISSING_VARS_LOG"
        continue
    fi
    > "$ENV_FILE"
    echo "${PREFIX}All required variables are set. Writing them to $ENV_FILE"
    for var in "${REQUIRED_VARS[@]}"; do
        printf "%s=%s\n" "$var" "${!var}" >> "$ENV_FILE"
    done
    echo "${PREFIX}...successfully wrote ${#REQUIRED_VARS[@]} variables to $ENV_FILE"
done

if [ -s "$MISSING_VARS_LOG" ]; then
    mapfile -t missing_vars < "$MISSING_VARS_LOG"
fi
rm "$MISSING_VARS_LOG"

if [ ${#missing_vars[@]} -gt 0 ]; then
    printf "Error: Missing Environment Variables: "
    for var in "${missing_vars[@]}"; do
        printf "%s " "${var}"
    done
    printf "\n"
    exit 1
else
    echo "Successfully processed all stack directories in $STACKS_DIR."
    exit 0
fi