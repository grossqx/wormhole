#!/bin/bash

backup_http_url="$WH_SERVER_API_URL/wh/rpi.backup-upload"

SYNC_MODE=$1
BACKUP_DIR=$2
REMOTE_BACKUP_DIR=$3
BACKUP_DESTINATION=$4


if [ -z "$SYNC_MODE" ]; then
    echo "ERROR: Synchronization mode not provided."
    echo "Usage: $0 {up | down | test | http-up}"
    echo "  up: Pushes data (Local -> Remote) via rsync/SSH (Incremental)."
    echo "  down: Pulls data (Remote -> Local) via rsync/SSH (Incremental)."
    echo "  test: Checks rsync/SSH prerequisites (dry-run)."
    echo "  http-up: Uploads $BACKUP_DIR as a .tar.gz archive via HTTP/S (Full Backup)."
    exit 1
fi

if [[ "$SYNC_MODE" != "up" && "$SYNC_MODE" != "down" && "$SYNC_MODE" != "test" && "$SYNC_MODE" != "http-up" ]]; then
    echo "ERROR: Invalid synchronization mode '$SYNC_MODE'."
    echo "Usage: $0 {up | down | test | http-up}"
    exit 1
fi

echo "Starting automated backup sync (Mode: $SYNC_MODE)..."

if [[ "$SYNC_MODE" != "http-up" ]]; then
    USERNAME=$(echo "$BACKUP_DESTINATION" | cut -d'@' -f1)
    HOST_AND_PORT=$(echo "$BACKUP_DESTINATION" | cut -d'@' -f2)
    if [[ "$HOST_AND_PORT" == *:* ]]; then # Check if port is specified
        REMOTE_HOST=$(echo "$HOST_AND_PORT" | cut -d':' -f1)
        REMOTE_SSH_PORT=$(echo "$HOST_AND_PORT" | cut -d':' -f2)
    else
        REMOTE_HOST="$HOST_AND_PORT"
        REMOTE_SSH_PORT="22" # Port is NOT specified: use default 22
    fi
    SSH_DESTINATION="${USERNAME}@${REMOTE_HOST}"
    echo "Destination: ${SSH_DESTINATION}, Port: ${REMOTE_SSH_PORT}"
fi

if [[ "$SYNC_MODE" != "http-up" ]]; then
    echo "Checking host reachability for $REMOTE_HOST..."
    ping -c 1 -W 5 "$REMOTE_HOST" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Can't reach host '$REMOTE_HOST'. Exiting."
        exit 1
    fi
    echo "Checking for non-interactive SSH access..."
    ssh -p "$REMOTE_SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=no "$SSH_DESTINATION" "exit" 2> /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: SSH key authentication failed for '$SSH_DESTINATION' on port '$REMOTE_SSH_PORT'."
        exit 1
    fi
fi

# -a: Archive mode (recursive, preserves metadata)
# -z: Compress file data during the transfer
# -e: Specifies the remote shell, essential for setting the port
#RSYNC_OPTIONS="-avz -e \"ssh -p $REMOTE_SSH_PORT\""
RSYNC_OPTIONS=(
    -avz 
    -e 
    "ssh -p $REMOTE_SSH_PORT"
)

case "$SYNC_MODE" in
    up)
        echo "Pushing to remote destination..."
        rsync "${RSYNC_OPTIONS[@]}" "$BACKUP_DIR" "$SSH_DESTINATION":"$REMOTE_BACKUP_DIR"
        ;;
    down)
        echo "Pulling from remote destination..."
        rsync "${RSYNC_OPTIONS[@]}" "$SSH_DESTINATION":"$REMOTE_BACKUP_DIR" "$BACKUP_DIR"
        ;;
    test)
        echo "Starting connectivity and permissions test (rsync dry-run)..."
        rsync "${RSYNC_OPTIONS[@]}" -n "$BACKUP_DIR" "$SSH_DESTINATION":"$REMOTE_BACKUP_DIR"
        
        if [ $? -eq 0 ]; then
            echo "Dry-run successful. All checks passed (Connectivity, Auth, Permissions)."
            exit 0
        else
            echo "Error: rsync dry-run failed."
            exit 1
        fi
        ;;
    http-up)
        echo "Starting HTTP upload..."
        BACKUP_BASENAME=$(wh-generate-backup-basename "$WH_INSTALL_CONFIG")
        TEMP_ARCHIVE="/tmp/${BACKUP_BASENAME}.tar.enc"
        echo "Creating temporary archive: ${BACKUP_BASENAME}..."
        if ! wh-backup "${BACKUP_DIR}" "/tmp" "${BACKUP_BASENAME}"; then
            echo "Error: ${BACKUP_DIR} backup FAILED (wh-backup exit code: $?)."
            exit 1
        fi
        echo "Uploading archive to ${backup_http_url}..."
        curl -s -H "Authorization: Bearer $WH_HARDWARE_API_KEY" -X POST -F "file=@$TEMP_ARCHIVE" "$backup_http_url"
        result=$?
        if [ ! ${result} -eq 0 ]; then
            echo "Error: curl HTTP upload failed - code ${result}. Cleaning up temporary archive..."
            rm -f "$TEMP_ARCHIVE"
            exit 1
        fi
        echo "Upload successful. Cleaning up temporary archive..."
        rm -f "$TEMP_ARCHIVE"
        ;;
esac

if [ $? -ne 0 ]; then
    echo "Error: sync operation failed."
    exit 1
fi

echo "Backup sync successfully completed!"