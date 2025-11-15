#!/bin/bash

function wh-generate-backup-basename() {
    local source_dir="$1"
    echo "backup_$(date +%Y%m%d_%H%M%S)_$(basename "$source_dir")"
}

function wh-count-backups() {
    local BACKUP_PATTERN_WILDCARD="backup_????????_??????_"
    local backup_dir="$1"
    local source_basename="$2"
    if [ -z "$backup_dir" ] || [ -z "$source_basename" ]; then
        echo "Error: Both backup directory and source basename must be provided." >&2
        echo "Usage: wh-count-backups <backup_directory> <source_dir_basename>" >&2
        return 1
    fi
    local pattern="${backup_dir}/${BACKUP_PATTERN_WILDCARD}${source_basename}.tar.enc"
    ls -1 $pattern 2>/dev/null | wc -l
    return 0
}

function wh-get-latest-backup() {
    local BACKUP_PATTERN_WILDCARD="backup_????????_??????_"
    local backup_dir="$1"
    local source_basename="$2"
    if [ -z "$backup_dir" ] || [ -z "$source_basename" ]; then
        echo "Error: Both backup directory and source basename must be provided." >&2
        echo "Usage: wh-get-latest-backup <backup_directory> <source_dir_basename>" >&2
        return 1
    fi
    local pattern="${backup_dir}/${BACKUP_PATTERN_WILDCARD}${source_basename}.tar.enc"
    local files=($(ls -1r $pattern 2>/dev/null))
    if [ ${#files[@]} -gt 0 ]; then
        echo "${files[0]}"
        return 0
    else
        return 1
    fi
}

function wh-get-oldest-backup() {
    local BACKUP_PATTERN_WILDCARD="backup_????????_??????_"
    local backup_dir="$1"
    local source_basename="$2"
    if [ -z "$backup_dir" ] || [ -z "$source_basename" ]; then
        echo "Error: Both backup directory and source basename must be provided." >&2
        echo "Usage: wh-get-oldest-backup <backup_directory> <source_dir_basename>" >&2
        return 1
    fi
    local pattern="${backup_dir}/${BACKUP_PATTERN_WILDCARD}${source_basename}.tar.enc"
    local files=($(ls -1 $pattern 2>/dev/null))
    if [ ${#files[@]} -gt 0 ]; then
        echo "${files[0]}"
        return 0
    else
        return 1
    fi
}

function wh-cleanup-oldest-backup() {
    local oldest_file
    local backup_dir="$1"
    local source_basename="$2"
    if [ -z "$backup_dir" ] || [ -z "$source_basename" ]; then
        echo "Error: Both backup directory and source basename must be provided." >&2
        echo "Usage: wh-cleanup-oldest-backup <backup_directory> <source_dir_basename>" >&2
        return 1
    fi
    oldest_file="$(wh-get-oldest-backup "$backup_dir" "$source_basename")"
    if [ $? -ne 0 ]; then
        echo "Info: No old backups found for source basename '$source_basename' in '$backup_dir'."
        return 0
    fi
    echo "Removing oldest backup: '$oldest_file'"
    rm -f "$oldest_file"
    if [ $? -eq 0 ]; then
        echo "Success: Oldest backup removed."
        return 0
    else
        echo "Error: Failed to remove oldest backup '$oldest_file'." >&2
        return 1
    fi
}

# wh-backup <source_directory> <output_directory>
# Creates an encrypted tar archive of the source_directory contents
# and saves it in the output_directory.
function wh-backup() {
    local source_dir="$1"
    local output_dir="$2"
    local set_filename="$3"
    local backup_filename
    local exit_code
    if [ -z "$source_dir" ] || [ -z "$output_dir" ]; then
        echo "Error: Both source directory and output directory must be provided." >&2
        echo "Usage: wh-backup <source_directory> <output_directory>" >&2
        return 1
    fi
    if [ ! -d "$source_dir" ]; then
        echo "Error: Source directory '$source_dir' does not exist." >&2
        return 1
    fi
    if [ ! -d "$output_dir" ]; then
        echo "Error: Output directory '$output_dir' does not exist." >&2
        return 1
    fi
    if [ -z "$set_filename" ]; then
        backup_filename="${output_dir}/$(wh-generate-backup-basename "$source_dir").tar.enc"
    else
        backup_filename="${output_dir}/${set_filename}.tar.enc"
    fi
    echo "Starting backup of '$source_dir' to '$backup_filename'"
    (
        cd "$source_dir" || { echo "Error: Cannot change to source directory $source_dir" >&2; return 1; }
        tar -pcf - . 2>/dev/null
    ) | openssl enc "${WH_CRYPTO_CIPHER}" -salt "${WH_CRYPTO_DERIVATION}" -k "${WH_CRYPTO_KEY}" > "$backup_filename"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "Success: Encrypted backup saved to '$backup_filename'"
        return 0
    else
        echo "Error: Backup failed (tar/openssl exited with code $exit_code)." >&2
        rm -f "$backup_filename"
        return 1
    fi
}

# wh-restore <input_encrypted_file> <output_directory>
# Decrypts and restores the contents of the encrypted tar file into the
# specified output_directory, preserving permissions.
function wh-restore() {
    local input_file="$1"
    local output_dir="$2"
    local exit_code
    if [ -z "$input_file" ] || [ -z "$output_dir" ]; then
        echo "Error: Both input file and output directory must be provided." >&2
        echo "Usage: wh-restore <input_encrypted_file> <output_directory>" >&2
        return 1
    fi
    if [ ! -f "$input_file" ]; then
        echo "Error: Input file '$input_file' does not exist." >&2
        return 1
    fi
    if [ ! -d "$output_dir" ]; then
        echo "Error: Output directory '$output_dir' does not exist." >&2
        return 1
    fi

    echo "Starting restore of '$input_file' into '$output_dir'"
    openssl enc -d "${WH_CRYPTO_CIPHER}" "${WH_CRYPTO_DERIVATION}" -k "${WH_CRYPTO_KEY}" -in "$input_file" | \
    tar -xpf - -C "$output_dir"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "Success: Encrypted backup restored to '$output_dir'"
        return 0
    else
        echo "Error: Restore failed (openssl/tar exited with code $exit_code)." >&2
        echo "Double-check that the file is not corrupted and the 'WH_CRYPTO_KEY' is correct." >&2
        return 1
    fi
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