# #!/bin/bash

UNBOUND_UID=1000
UNBOUND_GID=1000

echo "Creating logfile for unbound"
# Use the correct path based on the volume you are mounting for the logs
LOG_DIR="${STORAGE_PATH}/unbound/logs/"
LOG_FILE="${LOG_DIR}/unbound.log"

mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"

# Set ownership to the _unbound user's ID (1000)
sudo chown -R "${UNBOUND_UID}:${UNBOUND_GID}" "${LOG_FILE}"
sudo chmod 666 "${LOG_FILE}"
