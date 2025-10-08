#!/bin/bash

# Define the path to the rpi-clone git repository
rpiclone_repo="${WH_PATH}/repos/rpi-clone" 
total_steps=4

echo "[1/${total_steps}] Starting migration script"

echo "--- Block Device Information ---"
lsblk --output NAME,SIZE,FSTYPE,MOUNTPOINT,PARTLABEL,UUID,MODEL,TRAN,HOTPLUG
echo "--- Boot Information ---"
echo "Booted from $(mount | grep " / ")"
echo "------------------------------"

echo "[2/${total_steps}] Checking and updating rpi-clone repository at ${rpiclone_repo}"

if [ -d "$rpiclone_repo" ]; then
    echo "Directory ${rpiclone_repo} found. Performing git pull..."
    
    if cd "$rpiclone_repo"; then
        if git pull; then
            echo "rpi-clone repository updated successfully."
        else
            echo "Error: Failed to perform git pull in ${rpiclone_repo}."
            exit 1
        fi
        cd - > /dev/null # Go back to the previous directory silently
    else
        echo "Error: Failed to change directory to ${rpiclone_repo}."
        exit 1
    fi
else
    echo "Error: rpi-clone repository directory ${rpiclone_repo} does not exist. Please clone it first."
    exit 1
fi

echo "[3/${total_steps}] Copying rpi-clone files to /usr/local/sbin"

rpi_clone_script="${rpiclone_repo}/rpi-clone"
rpi_clone_setup_script="${rpiclone_repo}/rpi-clone-setup"

if [ -f "$rpi_clone_script" ] && [ -f "$rpi_clone_setup_script" ]; then
    echo "rpi-clone files found. Copying..."
    # Copy the files to the system sbin directory
    if sudo cp "$rpi_clone_script" "$rpi_clone_setup_script" /usr/local/sbin; then
        echo "rpi-clone and rpi-clone-setup copied to /usr/local/sbin successfully."
    else
        echo "Error: Failed to copy rpi-clone files."
        exit 1
    fi
else
    echo "Error: Required rpi-clone files not found in ${rpiclone_repo}."
    echo "Missing: $rpi_clone_script or $rpi_clone_setup_script"
    exit 1
fi

echo "[4/${total_steps}] Migration script complete"