#!/bin/bash

STACKS_DIR="${docker_configs}/stacks"
PREFIX="[docker manage] "
supported_compose_commands="up down pull create ps logs ls stats start stop restart kill"
supported_config_commands="services images networks volumes"

# Check if required paths are set
if [ -z "$docker_configs" ]; then
    echo "Error: STACKS_DIR (derived from docker_configs) is not set. Exiting."
    exit 1
fi

# Check if at least one argument is provided
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <${supported_compose_commands} ${supported_config_commands}> [stack1] [stack2]..."
  echo "  - The action to perform on the stacks."
  echo "  - Optional list of specific stack directories to process."
  echo "  - Commands 'up' and 'start' will be called in detached mode."
  exit 1
fi

ACTION=$1
shift # Shift arguments so $@ now contains the list of requested stacks
REQUESTED_STACKS=("$@")

manage_stack() {
  local stack_name=$1
  local action=$2
  local compose_file=""
  local search_dir="${STACKS_DIR}/${stack_name}"
  local potential_files=( "$search_dir"/*compose.y{a,}ml )

  for file_path in "${potential_files[@]}"; do
      if [ -f "$file_path" ]; then
          compose_file="$file_path"
          break
      fi
  done
  if [ -z "$compose_file" ]; then
    echo "${PREFIX}Warning: No Docker Compose file (*compose.yaml/yml) found in '$search_dir'. Skipping ${action} for ${stack_name}."
    return
  fi
  echo "${PREFIX}Performing 'docker compose ${action}' for stack $stack_name"
  if echo "$supported_config_commands" | grep -w -q "$action"; then
      sudo docker compose -f "$compose_file" config --"$action"
  elif echo "$supported_compose_commands" | grep -w -q "$action"; then
    if [[ $action == "up" || $action == "start" ]]; then
      sudo docker compose -f "$compose_file" "$action" -d
    else
      sudo docker compose -f "$compose_file" "$action"
    fi
  else
    echo "Error: unknown stack action: $action"
    echo "Supported actions are: $supported_compose_commands"
    exit 1
  fi
}

# Find all potential stack directories in STACKS_DIR
find "$STACKS_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' stack_dir; do
    STACK_NAME=$(basename "$stack_dir")
    # If specific stacks were requested, check if the current stack is one of them
    if [ ${#REQUESTED_STACKS[@]} -gt 0 ]; then
        IS_REQUESTED=false
        for req_stack in "${REQUESTED_STACKS[@]}"; do
            if [ "$STACK_NAME" == "$req_stack" ]; then
                IS_REQUESTED=true
                break
            fi
        done
        if [ "$IS_REQUESTED" = false ]; then
            continue
        fi
    fi
    manage_stack "$STACK_NAME" "$ACTION"
done
exit 0