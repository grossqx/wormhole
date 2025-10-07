#!/bin/bash

# Check if the first argument is provided and not empty
if [ -z "$1" ]; then
  echo "Error: No device specified. Please provide a device path like /dev/mmcblk0."
  exit 1
fi

DEVICE=$1

# Find all mounted partitions and extract the mount points.
MOUNT_POINTS=$(findmnt -n --raw | grep "$DEVICE" | awk '{print $1}')

# Check if any mount points were found.
if [ -z "$MOUNT_POINTS" ]; then
  echo "No partitions of ${DEVICE} were mounted."
  exit 0
fi

# Loop through each mount point and unmount it.
while read -r mount_point; do
  echo "Unmounting $mount_point..."
  sudo umount "$mount_point"
  if [ $? -eq 0 ]; then
    echo "Successfully unmounted $mount_point"
  else
    echo "Failed to unmount $mount_point"
    exit 1
  fi
done <<< "$MOUNT_POINTS"
exit 0