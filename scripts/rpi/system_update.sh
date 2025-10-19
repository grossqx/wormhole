#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

echo "Starting automated security maintenance at $(date):"

echo "Running apt update..."
apt update

echo "Running apt upgrade..."
apt-get -o Dpkg::Options::="--force-confold" --assume-yes upgrade -y

echo "Running apt autoremove and clean..."
apt autoremove -y
apt clean

echo "Restarting services affected by upgrades (if any)..."
needrestart -r a

echo "Checking for eeprom updates..."
if rpi-eeprom-update | grep -q "UPDATE AVAILABLE"; then
    rpi-eeprom-update -a
    echo "EEPROM update initiated. Will apply on next reboot."
else
    echo "No eeprom update required."
fi

echo "Maintenance complete."