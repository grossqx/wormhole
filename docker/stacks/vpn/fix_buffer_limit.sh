#!/bin/bash
#
# SCRIPT TO RESOLVE THE UNBOUND "so-rcvbuf" WARNING
# This script increases the net.core.rmem_max kernel setting to 1MB (1048576 bytes).

REQUIRED_VALUE=1048576
SYSCTL_FILE="/etc/sysctl.conf"
SYSCTL_KEY="net.core.rmem_max"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo or as root."
   exit 1
fi
echo "1. Checking current kernel limit for $SYSCTL_KEY"
# Get the current value, suppressing errors if the key isn't found
CURRENT_VALUE=$(sysctl -n $SYSCTL_KEY 2>/dev/null)
if [ -z "$CURRENT_VALUE" ]; then
    echo "Warning: $SYSCTL_KEY value could not be determined. Assuming default (low)."
    CURRENT_VALUE=0
fi
echo "Current limit: $CURRENT_VALUE"
echo "Target limit: $REQUIRED_VALUE (1 Megabyte)"
# Check if the current value is already sufficient
if [ "$CURRENT_VALUE" -ge "$REQUIRED_VALUE" ]; then
    echo "Limit is already sufficient. No changes to $SYSCTL_FILE needed."
    exit 0
fi
echo "2. Updating $SYSCTL_KEY in $SYSCTL_FILE"
# a) Delete any existing lines defining the key (edits/removes old value)
sed -i "/^$SYSCTL_KEY/d" "$SYSCTL_FILE"
# b) Append the new required value to the end of the file (adds new value)
echo "$SYSCTL_KEY = $REQUIRED_VALUE" >> "$SYSCTL_FILE"
echo "Configuration written to $SYSCTL_FILE."
echo "3. Applying new kernel configuration"
# Load the new settings from /etc/sysctl.conf
sysctl -p
echo "Success"
