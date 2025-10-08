#!/bin/bash
#
# mc skin configuration script
#
# It only modifies the configuration file if it already exists for the user,
# and now creates a .bak file of the original configuration before proceeding.

ROOT_SKIN="dark"
DEFAULT_SKIN="nicedark"

echo "Midnight Commander Skin Configuration"

set_mc_skin() {
    local USER_NAME=$1
    local SKIN_NAME=$2
    
    local USER_ENTRY=$(getent passwd "$USER_NAME")
    if [ -z "$USER_ENTRY" ]; then
        echo "Warning: User '$USER_NAME' not found in passwd database. Skipping."
        return 1
    fi
    
    local HOME_DIR=$(echo "$USER_ENTRY" | awk -F: '{print $6}')
    local MC_DIR="$HOME_DIR/.config/mc"
    local INI_FILE="$MC_DIR/ini"
    local BACKUP_FILE="$INI_FILE.bak"
    
    echo -n "Processing user '$USER_NAME' ($HOME_DIR)... "
    
    if [ ! -f "$INI_FILE" ]; then
        echo "SKIPPED (Configuration file '$INI_FILE' does not exist)."
        return 0
    fi
    
    cp "$INI_FILE" "$BACKUP_FILE"

    chown -R "$USER_NAME:$USER_NAME" "$MC_DIR" 2>/dev/null || true

    # Check if 'skin=' exists anywhere in the file
    if grep -q "^skin=" "$INI_FILE"; then
        # Replace the existing skin setting
        sed -i "s/^skin=.*/skin=$SKIN_NAME/" "$INI_FILE"
        echo "SUCCESS (Backup created at $BACKUP_FILE; Updated to '$SKIN_NAME')."
    elif grep -q "\[Midnight-Commander\]" "$INI_FILE"; then
        # The section exists but 'skin=' is missing: inject it immediately after the header
        sed -i "/\[Midnight-Commander\]/a skin=$SKIN_NAME" "$INI_FILE"
        echo "SUCCESS (Backup created at $BACKUP_FILE; Added '$SKIN_NAME' to section)."
    else
        # The section is missing entirely: append the section and the skin setting
        echo -e "\n[Midnight-Commander]\nskin=$SKIN_NAME" >> "$INI_FILE"
        echo "SUCCESS (Backup created at $BACKUP_FILE; Created section and set '$SKIN_NAME')."
    fi
}

set_mc_skin "root" "$ROOT_SKIN"

echo "Configuring Regular Users"

USERS=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1}')

if [ -z "$USERS" ]; then
    echo "No regular users found in the specified UID range (1000-59999)."
else
    for user in $USERS; do
        set_mc_skin "$user" "$DEFAULT_SKIN"
    done
fi

echo "Configuration Complete"
echo "Note: Users must restart Midnight Commander (mc) to apply the changes."
