#!/bin/bash

declare -i OPERATION_FAILED=0

MODE="$1"
if [[ "$MODE" != "backup" && "$MODE" != "restore" ]]; then
    echo "Usage: $0 {backup|restore} [STACKS...]"
    exit 1
fi
shift

echo "Starting docker ${MODE}..."

# Define exclusion patterns for system/volatile directories
EXCLUSION_PATTERNS='^/var/run/.*\.sock$|^/run/.*\.sock$|/etc/os-release|^/proc/|^/sys/|^/dev/|/log[s]?/|/temp[s]?/|/tmp/|/run/|/var/run/|/cache[s]?/'
STACKS="$@"

[[ -z $STACKS ]] && STACKS="" && echo "${MODE^} all stacks" || echo "${MODE^} stacks: ${STACKS}"

# Get all mount points
ALL_MOUNT_POINTS=$(${base_dir}/utils/docker_manage.sh mounts $STACKS | sort -u)
MOUNT_POINTS=$(echo "$ALL_MOUNT_POINTS" | grep -E -v "$EXCLUSION_PATTERNS")
EXCLUDED_MOUNT_POINTS=$(echo "$ALL_MOUNT_POINTS" | grep -E "$EXCLUSION_PATTERNS")

declare -a SKIP_MOUNTS=() && declare -a BACKUP_MOUNTS=()
declare -a BACKUP_MOUNTS_STORAGE=() && declare -a BACKUP_MOUNTS_CONFIG=() && declare -a BACKUP_MOUNTS_OTHER=()
declare -i total_to_process=0 && declare -i current_process=0
stacks_path=""

[[ -n "$EXCLUDED_MOUNT_POINTS" ]] && mapfile -t SKIP_MOUNTS < <(echo "$EXCLUDED_MOUNT_POINTS" | tr -d '"')
[[ -n "$MOUNT_POINTS" ]] && mapfile -t BACKUP_MOUNTS < <(echo "$MOUNT_POINTS" | tr -d '"')

function categorize_mounts() {
    echo "Scanning directories from compose files..."
    if [ ${#BACKUP_MOUNTS[@]} -gt 0 ]; then
        for MOUNT_PATH in "${BACKUP_MOUNTS[@]}"; do
            if [[ "$MOUNT_PATH" == "$docker_stacks" ]]; then
                MOUNT_POINT="stacks"
                if ! printf "%s\n" "${BACKUP_MOUNTS_STORAGE[@]}" | grep -Fxq -- "$MOUNT_POINT"; then
                    stacks_path="$MOUNT_PATH"
                    echo " + <stacks>  $MOUNT_POINT $MOUNT_PATH"
                    total_to_process=$((total_to_process + 1))
                else
                    echo " = Skipping $MOUNT_PATH because it was already included in ${MOUNT_POINT}"
                fi
            elif [[ "$MOUNT_PATH" == "$docker_volumes"* ]]; then
                MOUNT_POINT="${MOUNT_PATH#${docker_volumes}/}"
                MOUNT_POINT="${MOUNT_POINT%%/*}"
                if ! printf "%s\n" "${BACKUP_MOUNTS_STORAGE[@]}" | grep -Fxq -- "$MOUNT_POINT"; then
                    BACKUP_MOUNTS_STORAGE+=("$MOUNT_POINT")
                    echo " + <storage> $MOUNT_POINT $MOUNT_PATH"
                    total_to_process=$((total_to_process + 1))
                else
                    echo " # <storage> (skipping - included in ${MOUNT_POINT}) ${MOUNT_PATH}"
                fi
            elif [[ "$MOUNT_PATH" == "$docker_configs"* ]]; then
                MOUNT_POINT="${MOUNT_PATH#${docker_configs}/}"
                MOUNT_POINT="${MOUNT_POINT%%/*}"
                if ! printf "%s\n" "${BACKUP_MOUNTS_CONFIG[@]}" | grep -Fxq -- "$MOUNT_POINT"; then
                    BACKUP_MOUNTS_CONFIG+=("$MOUNT_POINT")
                    echo " + <configs> $MOUNT_POINT $MOUNT_PATH"
                    total_to_process=$((total_to_process + 1))
                else
                    echo " # <configs> (skipping - included in ${MOUNT_POINT}) ${MOUNT_PATH}"
                fi
            else
                BACKUP_MOUNTS_OTHER+=("$MOUNT_PATH")
                echo " + <other>   $MOUNT_PATH"
                total_to_process=$((total_to_process + 1))
            fi
        done
        echo "Found ${total_to_process} total mounted directories to ${MODE}."
        echo "Local backup directory '${local_backup_dir}'"
    elif [ ${#BACKUP_MOUNTS[@]} -eq 0 ]; then
        echo "No valid mounts found to ${MODE}."
    fi
}

categorize_mounts

case "$MODE" in
    backup)
        echo "Skipping system mounts: ${#SKIP_MOUNTS[@]}"
        for MOUNT in "${SKIP_MOUNTS[@]}"; do
            echo " - [${current_process}/${total_to_process}] (SKIP) $MOUNT"
        done

        if [[ -z $stacks_path ]]; then
            echo "Stacks directory not being backed up"
        else
            current_process=$((current_process + 1))
            echo "Stacks directory:" && DESIGNATED_MOUNT="${stacks_path}"
            echo " - [${current_process}/${total_to_process}] (STACKS) $DESIGNATED_MOUNT"
            dest="${local_backup_dir}/docker/stacks" && mkdir -p "$dest"
            if ! wh-backup "$DESIGNATED_MOUNT" "$dest"; then
                echo "Error: STACKS backup FAILED (wh-backup exit code: $?). Continuing..." >&2
                OPERATION_FAILED=1
            fi
        fi

        echo "Total data mounts for back up: ${#BACKUP_MOUNTS_STORAGE[@]}"
        for MOUNT in "${BACKUP_MOUNTS_STORAGE[@]}"; do
            current_process=$((current_process + 1))
            echo " - [${current_process}/${total_to_process}] (DATA) $MOUNT"
            dest="${local_backup_dir}/docker/storage" && mkdir -p "$dest"
            if ! wh-backup "${docker_volumes}/${MOUNT}" "$dest"; then
                echo "Error: DATA mount '$MOUNT' backup FAILED (wh-backup exit code: $?). Continuing..." >&2
                OPERATION_FAILED=1
            fi
        done

        echo "Total configuration mounts for back up: ${#BACKUP_MOUNTS_CONFIG[@]}"
        for MOUNT in "${BACKUP_MOUNTS_CONFIG[@]}"; do
            current_process=$((current_process + 1))
            echo " - [${current_process}/${total_to_process}] (CONF) $MOUNT"
            dest="${local_backup_dir}/docker/configs" && mkdir -p "$dest"
            if ! wh-backup "${docker_configs}/${MOUNT}" "$dest"; then
                echo "Error: CONFIG mount '$MOUNT' backup FAILED (wh-backup exit code: $?). Continuing..." >&2
                OPERATION_FAILED=1
            fi
        done

        echo "Total uncategorized mounts for back up: ${#BACKUP_MOUNTS_OTHER[@]}"
        for MOUNT in "${BACKUP_MOUNTS_OTHER[@]}"; do
            current_process=$((current_process + 1))
            echo " - [${current_process}/${total_to_process}] (OTHER) $MOUNT"
            dest="${local_backup_dir}/docker/other" && mkdir -p "$dest"
            if ! wh-backup "$MOUNT" "$dest"; then
                echo "Error: OTHER mount '$MOUNT' backup FAILED (wh-backup exit code: $?). Continuing..." >&2
                OPERATION_FAILED=1
            fi
        done
        ;;

    restore)
        echo "Skipping system mounts (restore not applicable): ${#SKIP_MOUNTS[@]}"
        for MOUNT in "${SKIP_MOUNTS[@]}"; do
            echo " - (SKIP) $MOUNT"
        done
        
        if [[ -z $stacks_path ]]; then
            echo "Stacks directory not being restored (no path found)"
        else
            current_process=$((current_process + 1))
            OUTPUT_DIR="${stacks_path}" && mkdir -p ${OUTPUT_DIR}
            BACKUP_CAT_DIR="${local_backup_dir}/docker/stacks"
            INPUT_FILE=$(wh-get-latest-backup ${BACKUP_CAT_DIR} "stacks")            
            if [ "$?" -eq 0 ]; then
                echo " - [${current_process}/${total_to_process}] (STACKS) Restoring $(basename "$INPUT_FILE") to $OUTPUT_DIR"
                if ! wh-restore "$INPUT_FILE" "$OUTPUT_DIR"; then
                    echo "Error: STACKS restore FAILED (wh-restore exit code: $?). Continuing..." >&2
                    OPERATION_FAILED=1
                fi
            else
                echo " - [${current_process}/${total_to_process}] (STACKS) Skipping restore (No latest backup found in $BACKUP_CAT_DIR)"
            fi
        fi

        echo "Total data mounts for restore: ${#BACKUP_MOUNTS_STORAGE[@]}"
        for MOUNT in "${BACKUP_MOUNTS_STORAGE[@]}"; do
            current_process=$((current_process + 1))
            OUTPUT_DIR="${docker_volumes}/${MOUNT}" && mkdir -p ${OUTPUT_DIR}
            BACKUP_CAT_DIR="${local_backup_dir}/docker/storage"
            INPUT_FILE=$(wh-get-latest-backup ${BACKUP_CAT_DIR} ${MOUNT}) 2>&1
            if [ "$?" -eq 0 ]; then
                echo " - [${current_process}/${total_to_process}] (DATA) Restoring $(basename "$INPUT_FILE") to $OUTPUT_DIR"
                if ! wh-restore "$INPUT_FILE" "$OUTPUT_DIR"; then
                    echo "Error: DATA mount '$MOUNT' restore FAILED (wh-restore exit code: $?). Continuing..." >&2
                    OPERATION_FAILED=1
                fi
            else
                echo " - [${current_process}/${total_to_process}] (DATA) Skipping restore for $MOUNT (No latest backup found in $BACKUP_CAT_DIR)"
            fi
        done

        echo "Total configuration mounts for restore: ${#BACKUP_MOUNTS_CONFIG[@]}"
        for MOUNT in "${BACKUP_MOUNTS_CONFIG[@]}"; do
            current_process=$((current_process + 1))
            OUTPUT_DIR="${docker_configs}/${MOUNT}" && mkdir -p ${OUTPUT_DIR}
            BACKUP_CAT_DIR="${local_backup_dir}/docker/configs"
            INPUT_FILE=$(wh-get-latest-backup ${BACKUP_CAT_DIR} ${MOUNT}) 
            if [ "$?" -eq 0 ]; then
                echo " - [${current_process}/${total_to_process}] (CONF) Restoring $(basename "$INPUT_FILE") to $OUTPUT_DIR"
                if ! wh-restore "$INPUT_FILE" "$OUTPUT_DIR"; then
                    echo "Error: CONFIG mount '$MOUNT' restore FAILED (wh-restore exit code: $?). Continuing..." >&2
                    OPERATION_FAILED=1
                fi
            else
                echo " - [${current_process}/${total_to_process}] (CONF) Skipping restore for $MOUNT (No latest backup found in $BACKUP_CAT_DIR)"
            fi
        done

        echo "Total uncategorized mounts for restore: ${#BACKUP_MOUNTS_OTHER[@]}"
        for MOUNT in "${BACKUP_MOUNTS_OTHER[@]}"; do
            current_process=$((current_process + 1))
            OUTPUT_DIR="$MOUNT" && mkdir -p ${OUTPUT_DIR}
            BACKUP_CAT_DIR="${local_backup_dir}/docker/other"
            INPUT_FILE=$(wh-get-latest-backup ${BACKUP_CAT_DIR} $(basename "$MOUNT")) 
            if [ "$?" -eq 0 ]; then
                echo " - [${current_process}/${total_to_process}] (OTHER) Restoring $(basename "$INPUT_FILE") to $OUTPUT_DIR"
                if ! wh-restore "$INPUT_FILE" "$OUTPUT_DIR"; then
                    echo "Error: OTHER mount '$MOUNT' restore FAILED (wh-restore exit code: $?). Continuing..." >&2
                    OPERATION_FAILED=1
                fi
            else
                echo " - [${current_process}/${total_to_process}] (OTHER) Skipping restore for $MOUNT (No latest backup found in $BACKUP_CAT_DIR)"
            fi
        done
        ;;
    
    *)
        echo "Error: Invalid mode '$MODE'. Use 'backup' or 'restore'."
        exit 1
        ;;
esac

echo "Docker ${MODE} complete."
if [[ "$OPERATION_FAILED" -eq 1 ]]; then
    echo "Failure: One or more ${MODE} operations failed." >&2
    exit 1
fi
exit 0