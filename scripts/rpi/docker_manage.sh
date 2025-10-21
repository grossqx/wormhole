#!/bin/bash

PREFIX="[docker manage] "
commands_compose="up down pull create ps logs ls stats start stop restart kill"
commands_config="show services images networks volumes"
commands_custom="list mounts"

if [ -z "$docker_stacks" ]; then
    echo "Error: docker_stacks is not set. Exiting."
    exit 1
fi

# Check if at least one argument is provided
if [ "$#" -lt 1 ]; then
  echo "Usage: <command> [stack1] [stack2]..."
  echo "  - The action to perform on the stacks."
  echo "  - Optional list of specific stacks to process."
  echo "  docker compose commands: ${commands_compose}"
  echo "  docker compose config options: ${commands_config}"
  echo "  other commands: ${commands_custom}"
  exit 1
fi

ACTION=$1
shift
REQUESTED_STACKS=("$@")

list_local_mounts() {
    local compose_file=$1
    local yq_query=".services[].volumes[]? | select(.type == \"bind\") | .source"
    sudo docker compose -f "$compose_file" config | \
        yq "$yq_query" | \
        sort -u
}

function manage_stack() {
  local stack_name=$1
  local action=$2
  local compose_file=""
  local search_dir="${docker_stacks}/${stack_name}"
  local potential_files=( "$search_dir"/*compose.y{a,}ml )

  for file_path in "${potential_files[@]}"; do
      if [ -f "$file_path" ]; then
          compose_file="$file_path"
          break
      fi
  done
  if [ -z "$compose_file" ]; then
    echo "Error: No Docker Compose file (*compose.yaml/yml) found in '$search_dir'. Skipping ${action} for '${stack_name}'."
    return
  fi
  if echo "$commands_custom" | grep -w -q "$action"; then
    if [[ $action == "mounts" ]]; then
        source "${docker_dir}/environment.sh"
        list_local_mounts "$compose_file"
        return
    fi
  elif echo "$commands_config" | grep -w -q "$action"; then
      if [[ $action == "show" ]]; then
        sudo docker compose -f "$compose_file" config
      else
        sudo docker compose -f "$compose_file" config --"$action"
      fi
  elif echo "$commands_compose" | grep -w -q "$action"; then
    echo "Running 'docker compose ${action}' for stack '${stack_name}'"
    if [[ $action == "up" ]]; then
      sudo docker compose -f "$compose_file" "$action" -d
    else
      sudo docker compose -f "$compose_file" "$action"
    fi
  else
    echo "Error: unknown stack action: '$action'"
    echo "Supported actions are: $commands_compose ${commands_custom}"
    exit 1
  fi
}

# Find all potential stack directories in docker_stacks
find "$docker_stacks" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' stack_dir; do
    STACK_NAME=$(basename "$stack_dir")
    if [[ $ACTION == "list" || $ACTION == "ls" ]]; then
        echo "$STACK_NAME"
        continue
    fi
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