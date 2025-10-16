#!/bin/bash
#
# Script: nfs_config.sh
# Purpose: Installs NFS packages and/or sets up a bind mount for NFS export
#          on Raspberry Pi OS, including configuration of /etc/exports.
#
# Usage:
#   Install packages: ./nfs_config.sh -i
#   Setup bind mount & export: ./nfs_config.sh <source_dir> <export_name> <client> <options>
#   Example: ./nfs_config.sh /home/users users 192.168.1.0/24 rw,sync,no_subtree_check
#            ./nfs_config.sh /mnt/data shared_data 10.0.0.5 ro

EXPORT_BASE="/export"
SOURCE_DIR=$1
EXPORT_NAME=$2
CLIENT_ACCESS=$3
EXPORT_OPTIONS=$4
EXPORT_DIR="${EXPORT_BASE}/${EXPORT_NAME}"

install_nfs_packages() {
    echo "Installing NFS server (nfs-kernel-server) and client (nfs-common) packages..."
    sudo apt update
    if sudo apt install -y nfs-kernel-server nfs-common; then
        echo "NFS packages installed successfully."
        sudo systemctl enable --now nfs-server
        echo "NFS server service started and enabled for boot."
        return 0
    else
        echo "Error: apt installation failed."
        return 1
    fi
}

if [ "$1" == "-i" ]; then
    install_nfs_packages
    exit $?
fi

if [ -z "$SOURCE_DIR" ] || [ -z "$EXPORT_NAME" ] || [ -z "$CLIENT_ACCESS" ] || [ -z "$EXPORT_OPTIONS" ]; then
    echo "Usage (Setup Bind Mount & Export): $0 <source_dir> <export_name> <client> <options>"
    echo "Example: $0 /home/users users 192.168.1.0/24 rw,sync,no_subtree_check"
    echo "Usage (Install NFS Packages): $0 -i"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

echo "[1]. Creating the export directory: ${EXPORT_DIR}"
sudo mkdir -p "${EXPORT_DIR}"

echo "[2]. Setting permissions on ${EXPORT_BASE}"
sudo chmod -R 777 "${EXPORT_BASE}"

echo "[3]. Creating the bind mount: ${SOURCE_DIR} -> ${EXPORT_DIR}"
if sudo mount --bind "${SOURCE_DIR}" "${EXPORT_DIR}"; then
    echo "Bind mount successful."
else
    echo "Error: Failed to create bind mount. Exiting."
    exit 1
fi

echo "[4]. Adding entry to /etc/fstab for persistence"
FSTAB_LINE="${SOURCE_DIR}    ${EXPORT_DIR}    none    bind    0    0"

if grep -Fxq "$FSTAB_LINE" /etc/fstab; then
    echo "Entry already exists in /etc/fstab."
else
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
    echo "Added line to /etc/fstab: $FSTAB_LINE"
fi

echo "[5]. Configuring NFS export in /etc/exports"
EXPORTS_LINE="${EXPORT_DIR}    ${CLIENT_ACCESS}(${EXPORT_OPTIONS})"

if grep -Fxq "$EXPORTS_LINE" /etc/exports; then
    echo "Export entry already exists in /etc/exports."
else
    echo "$EXPORTS_LINE" | sudo tee -a /etc/exports > /dev/null
    echo "Added line to /etc/exports: $EXPORTS_LINE"
fi

echo "[6]. Applying new NFS export rules"
if sudo exportfs -ra; then
    echo "NFS export rules reloaded successfully."
else
    echo "Error: Failed to reload NFS exports. Check /etc/exports."
fi

echo "The directory ${SOURCE_DIR} is now exported to ${CLIENT_ACCESS} at ${EXPORT_DIR}"