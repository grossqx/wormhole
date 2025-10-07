#!/bin/bash

# ==============================================================================
# This script uninstalls the WORMHOLE application by systematically removing
# all associated files, folders, and environment variables.
#
# It performs the following actions:
# 1. Deletes a predefined list of WORMHOLE application files and directories.
# 2. Removes the 'WORMHOLE_API_KEY', 'WORMHOLE_API_URL' and WORMHOLE_CRYPTO_KEY
#    declarations from the user's ~/.bashrc file.
# 3. Deletes itself.
#
# ==============================================================================

# List of files and folders to delete relative to the script's directory.
files_to_delete=(
  "hello.sh"
  "install.sh"
  "start.sh"
  "update.sh"
)

folders_to_delete=(
  "common"
  "res"
  "rpi"
  "utils"
)

symlink_path="/usr/local/bin/wormhole-installer"
bashrc_path="$HOME/.bashrc"
persistent_data_dir="$HOME/.config/wormhole"
cache_dir="$HOME/.cache/wormhole"
config_memos_dir="$HOME/wormhole"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
echo "Script is located at: $script_dir"
cd -- "$script_dir" || { echo "Failed to change to script directory. Exiting." >&2; exit 1; }
echo "Beginning uninstallation..."

# Loop through the files to delete.
for file in "${files_to_delete[@]}"; do
    if [ -f "$file" ]; then
        echo "Deleting file: $file"
        rm "$file"
    else
        echo "File not found, skipping: $file"
    fi
done

# Loop through the folders to delete.
for folder in "${folders_to_delete[@]}"; do
    if [ -d "$folder" ]; then
        echo "Deleting folder: $folder"
        rm -rf "$folder"
    else
        echo "Folder not found, skipping: $folder"
    fi
done

echo "Deleting persistent user data in : $persistent_data_dir"
rm -rf "$persistent_data_dir"

echo "Deleting cache in : $cache_dir"
rm -rf "$cache_dir"

# Remove the specified lines from ~/.bashrc
if [ -f "$bashrc_path" ]; then
    echo "Checking for and removing WORMHOLE API variables from $bashrc_path"
    sed -i '/^export WORMHOLE_API_KEY=.*$/d' "$bashrc_path"
    sed -i '/^export WORMHOLE_API_URL=.*$/d' "$bashrc_path"
    sed -i '/^export WORMHOLE_CRYPTO_KEY=.*$/d' "$bashrc_path"
else
    echo "$bashrc_path not found, skipping variable removal."
fi

echo "Removing the symlink ${symlink_path}."
sudo rm "${symlink_path}"

echo "Uninstallation complete."
echo "Environment variables WORMHOLE_API_KEY, WORMHOLE_API_URL and WORMHOLE_CRYPTO_KEY were unset for the next session."
echo "Any memos left from installations are left untouched in ${config_memos_dir}. Please move them to a secure place."

rm -- ${script_dir}/uninstall.sh