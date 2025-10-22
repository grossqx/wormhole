#!/bin/bash

rpiclone_repo="${WH_PATH}/repos/rpi-clone"
plan="${WH_HOME}/migration_order.sh"
storage_functions="/etc/profile.d/wh_storage.sh"
binary_dir="/usr/local/sbin"
total_steps=6

function missing_device(){
    local device_name="$1"
    local device_rule="$2"
    echo "Error: $device_name boot device missing and expected by the configuration (${device_rule})"
    echo "Please connect the storage device and reboot or reconfigure expected boot devices."
}

function schedule_migration(){
    if [ ! -f $plan ]; then
        echo "--- New migration plan created"
        echo "#!/bin/bash" > $plan
        echo "#" >> $plan
        echo "# Migration" >> $plan
        echo >> $plan
        echo "set -e" >> $plan
        echo >> $plan
    fi
}

function schedule_cloning(){
    local from="$1"
    local to="$2"
    schedule_migration
    echo "--- Cloning from ${from} to ${to} scheduled"
    echo "# Clone current drive to ${to}" >> $plan
    echo "$binary_dir/rpi-clone $to -U --exclude='$plan'" >> $plan
}

function schedule_boot_order_change(){
    local to="$1"
    schedule_migration
    echo "--- Boot order change to ${to} scheduled"
    echo "# Set boot order to $to" >> $plan
    echo "${WH_PATH}/utils/set_boot_order.sh -device $to" >> $plan
}

echo "[1/${total_steps}] Starting migration script"

if [ ! -f "$storage_functions" ]; then
    echo "Error: ${storage_functions} is missing"
    exit 1
fi
source $storage_functions

echo "Block Device Information"
lsblk --output NAME,SIZE,FSTYPE,MOUNTPOINT,PARTLABEL,UUID,MODEL,TRAN,HOTPLUG
echo "Boot Information"
echo "Booted from $(mount | grep " / ")"

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
    echo "Error: rpi-clone repository directory ${rpiclone_repo} does not exist. Clone it first."
    exit 1
fi

echo "[3/${total_steps}] Copying rpi-clone files to ${binary_dir}"
rpi_clone_script="${rpiclone_repo}/rpi-clone"
rpi_clone_setup_script="${rpiclone_repo}/rpi-clone-setup"
if [ -f "$rpi_clone_script" ] && [ -f "$rpi_clone_setup_script" ]; then
    echo "rpi-clone files found. Copying..."
    if sudo cp "$rpi_clone_script" "$rpi_clone_setup_script" ${binary_dir}; then
        echo "rpi-clone and rpi-clone-setup copied to ${binary_dir} successfully."
    else
        echo "Error: Failed to copy rpi-clone files."
        exit 1
    fi
else
    echo "Error: Required rpi-clone files not found in ${rpiclone_repo}."
    echo "Missing: $rpi_clone_script or $rpi_clone_setup_script"
    exit 1
fi

echo "[4/${total_steps}] Checking storage devices"
current_boot_path=$(mount | grep " / " | awk '{print $1}')
echo "Currently booted from: ${current_boot_path}"
boot_primary_found=0
boot_secondary_found=0
boot_current=""
if [ ! -z "$WH_BOOT_DEVICE" ]; then
    resolved_device=$(wh-storage-resolve "$WH_BOOT_DEVICE")
    wh_resolve_status=$?
    echo "Primary boot device is configured as ${WH_BOOT_DEVICE}"
    if [ $wh_resolve_status -eq 0 ]; then
        echo "Assigned device ${resolved_device}:"
        lsblk ${resolved_device}
        boot_primary_found=1
        if echo "$current_boot_path" | grep -q "$resolved_device"; then
            echo "Currently booted from the primary device: ${resolved_device}"
            boot_current="primary"
        fi
    else
        missing_device "Primary" "$WH_BOOT_DEVICE"
    fi
else
    echo "Primary boot device not configured (WH_BOOT_DEVICE is empty)."
fi
if [ ! -z "$WH_BOOT_DEVICE2" ]; then
    resolved_device2=$(wh-storage-resolve "$WH_BOOT_DEVICE2")
    wh_resolve_status2=$?
    echo "Secondary boot device is configured as ${WH_BOOT_DEVICE2}"
    if [ $wh_resolve_status2 -eq 0 ]; then
        echo "Assigned device ${resolved_device2}:"
        lsblk ${resolved_device2}
        boot_secondary_found=1
        if echo "$current_boot_path" | grep -q "$resolved_device2"; then
            echo "Currently booted from the secondary device: ${resolved_device2}"
            boot_current="secondary"
        fi
    else
        missing_device "Secondary" "$WH_BOOT_DEVICE2"
    fi
else
    echo "Secondary boot device not configured (WH_BOOT_DEVICE2 is empty)."
fi

echo "[5/${total_steps}] Making a migration plan"
if [[ $boot_current == "primary" ]]; then
    if [[ $boot_secondary_found -eq 1 ]]; then
        echo "Scheduling cloning from ${resolved_device} (primary) to ${resolved_device2} (secondary)"
        schedule_cloning "$resolved_device" "$resolved_device2"
        ${WH_PATH}/utils/set_boot_order.sh -check
        if [[ $? -eq 0 ]]; then
            echo "Boot order already explicitly set"
        else
            echo "Boot order not explicitly set"
            schedule_boot_order_change "${resolved_device}"
        fi
    else
        error_message="Secondary boot device '${WH_BOOT_DEVICE2}' not found."
    fi
elif [[ $boot_current == "secondary" ]]; then
    if [[ $boot_primary_found -eq 1 ]]; then
        echo "Scheduling cloning from ${resolved_device2} (secondary) to ${resolved_device} (primary)"
        schedule_cloning "$resolved_device2" "$resolved_device"
        schedule_boot_order_change "${resolved_device}"
    else
        error_message="Primary boot device '${WH_BOOT_DEVICE}' not found."
    fi
else
    echo "Error: Migration not possible. Currently booted from neither primary nor the secondary configured boot device."
    exit 1
fi

if [ ! -f "$plan" ]; then
    echo "$error_message - migration canceled."
    exit 1
fi

echo "------ Migration plan created: --------"
cat $plan
echo "---------------------------------------"
echo "Plan will be automatically run by wormholed.service on next boot"
echo "To cancel the migration: sudo rm $plan"
echo "[6/${total_steps}] Migration script complete"