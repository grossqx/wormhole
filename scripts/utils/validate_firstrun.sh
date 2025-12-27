#!/bin/bash

set -e

TARGET_DEVICE=$1
FIRSTRUN_SCRIPT=$2
WIFI_REGION=$3

if [[ -z "$TARGET_DEVICE" || -z "$FIRSTRUN_SCRIPT" ]]; then
    echo "Usage: $0 <target_device> <firstrun_script_path> [wifi_region]"
    exit 1
fi

BOOT_PART=$(lsblk -lno NAME,LABEL "$TARGET_DEVICE" | grep "bootfs" | awk '{print "/dev/" $1}')

if [[ -z "$BOOT_PART" ]]; then
    echo "Error: Could not find partition labeled 'bootfs' on $TARGET_DEVICE"
    exit 1
fi

EXISTING_MOUNT=$(lsblk -no MOUNTPOINT "$BOOT_PART" | grep -v "^$" || true)
if [[ -n "$EXISTING_MOUNT" ]]; then
    echo "Partition $BOOT_PART is currently mounted at $EXISTING_MOUNT. Unmounting..."
    sudo umount -l "$BOOT_PART" || { echo "Error: Failed to unmount existing partition."; exit 1; }
fi

MOUNT_POINT=$(mktemp -d)

cleanup() {
    if mountpoint -q "$MOUNT_POINT"; then
        echo "Finalizing and unmounting $BOOT_PART..."
        sync
        sudo umount -l "$MOUNT_POINT"
    fi
    if [ -d "$MOUNT_POINT" ]; then
        rmdir "$MOUNT_POINT"
    fi
}
trap cleanup EXIT

echo "Mounting $BOOT_PART to $MOUNT_POINT..."
sudo mount "$BOOT_PART" "$MOUNT_POINT"

DEST_FIRST_RUN="$MOUNT_POINT/firstrun.sh"

if [[ ! -f "$DEST_FIRST_RUN" ]]; then
    echo "firstrun.sh not found. Copying from $FIRSTRUN_SCRIPT..."
    sudo cp "$FIRSTRUN_SCRIPT" "$DEST_FIRST_RUN"
    sudo chmod +x "$DEST_FIRST_RUN"
else
    echo "firstrun.sh exists. Checking for differences..."
    if ! diff -q "$FIRSTRUN_SCRIPT" "$DEST_FIRST_RUN" > /dev/null; then
        echo "Error: firstrun.sh exists but differs from source script."
        exit 1
    fi
    echo "firstrun.sh is already up to date."
fi

CMDLINE_FILE="$MOUNT_POINT/cmdline.txt"
if [[ ! -f "$CMDLINE_FILE" ]]; then
    echo "Error: cmdline.txt not found in partition bootfs."
    exit 1
fi

CURRENT_CMDLINE=$(cat "$CMDLINE_FILE")

SYSTEMD_PARAMS="systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target"

if [[ -n "$WIFI_REGION" ]]; then
    REGDOM_PARAM="cfg80211.ieee80211_regdom=${WIFI_REGION}"
    if [[ $CURRENT_CMDLINE == *"cfg80211.ieee80211_regdom="* ]]; then
        CURRENT_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed "s/cfg80211\.ieee80211_regdom=[^ ]*/$REGDOM_PARAM/")
    else
        CURRENT_CMDLINE="$CURRENT_CMDLINE $REGDOM_PARAM"
    fi
else
    echo "No WiFi region provided. Skipping cfg80211 configuration."
fi

for param in $SYSTEMD_PARAMS; do
    if [[ $CURRENT_CMDLINE != *"$param"* ]]; then
        CURRENT_CMDLINE="$CURRENT_CMDLINE $param"
    fi
done

echo "$CURRENT_CMDLINE" | tr -s ' ' | sudo tee "$CMDLINE_FILE" > /dev/null

echo "Verifying changes in cmdline.txt..."
VERIFY_CMDLINE=$(cat "$CMDLINE_FILE")

if [[ -n "$WIFI_REGION" ]]; then
    if [[ "$VERIFY_CMDLINE" != *"$REGDOM_PARAM"* ]]; then
        echo "Verification FAILED: WiFi region parameter not found or incorrect."
        exit 1
    fi
fi

for param in $SYSTEMD_PARAMS; do
    if [[ "$VERIFY_CMDLINE" != *"$param"* ]]; then
        echo "Verification FAILED: Missing parameter $param"
        exit 1
    fi
done

echo "Verification successful. cmdline.txt is correct."