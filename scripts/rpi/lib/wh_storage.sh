#!/bin/bash

function wh-backup(){
    echo "Backup"
}

function wh-restore(){
    echo "Restore"
}

function wh-storage-resolve(){
    local input_device="$1"
    local resolved_device="$input_device"
    local device_path=""
    local result_code=1
    if [[ -b "$input_device" ]]; then # Check if the input is already a valid block device
        echo "$input_device"
        return 0
    fi
    case "$input_device" in # Resolve symbolic names to a device path
        "USB")
            # Find the first connected USB mass storage device (TYPE=disk, TRAN=usb)
            device_path=$(lsblk -o NAME,TRAN,TYPE -n -r | awk '$2=="usb" && $3=="disk" {print "/dev/"$1; exit}')
            if [[ -n "$device_path" ]]; then
                resolved_device="$device_path"
                result_code=0
            else
                resolved_device="Could not find a connected USB disk."
                result_code=1
            fi
            ;;
        "NVME")
            # Find the first NVMe disk device (name starts with nvme...n#)
            device_path=$(lsblk -o NAME,TYPE -n -r | awk '$1 ~ /^nvme.*n[0-9]$/ && $2=="disk" {print "/dev/"$1; exit}')
            if [[ -n "$device_path" ]]; then
                resolved_device="$device_path"
                result_code=0
            else
                resolved_device="Could not find an NVMe disk."
                result_code=1
            fi
            ;;
        "SDCARD")
            # Find the first SD/MMC device (name starts with mmcblk)
            device_path=$(lsblk -o NAME,TYPE -n -r | awk '$1 ~ /^mmcblk[0-9]/ && $2=="disk" {print "/dev/"$1; exit}')
            if [[ -n "$device_path" ]]; then
                resolved_device="$device_path"
                result_code=0
            else
                resolved_device="Could not find an SDCARD/MMC device."
                result_code=1
            fi
            ;;

        *)
            # Handle incomplete device names. Remove common path fragments to get the device name base
            local clean_name
            clean_name="${input_device#*/dev/}"
            clean_name="${clean_name#dev/}"
            clean_name="${clean_name#/}"
            clean_name="${clean_name%/}"
            # Find the first block device starting with the clean name
            if [[ -n "$clean_name" ]]; then
                device_path=$(lsblk -o NAME,TYPE -n -r | awk -v prefix="$clean_name" '$1 ~ "^" prefix && $2=="disk" {print "/dev/"$1; exit}')
            fi
            if [[ -n "$device_path" ]]; then
                resolved_device="$device_path"
                result_code=0
            else
                resolved_device="Device '$input_device' could not be resolved to a valid block device."
                result_code=1
            fi
            ;;
    esac
    if [[ "$result_code" -eq 0 ]]; then
        if [[ ! -b "$resolved_device" ]]; then
            # This handles edge cases where lsblk found the name, but the path is not a block device (e.g. symlink issue)
            resolved_device="Path '$resolved_device' is not a valid block device."
            result_code=1
        fi
    fi
    echo "$resolved_device"
    return $result_code
}