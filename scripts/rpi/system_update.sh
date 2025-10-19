#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

echo "Starting a regular package update at $(date):"

echo "Running apt update..."
apt-get update

echo "Running apt upgrade..."
apt-get -o Dpkg::Options::="--force-confold" --assume-yes upgrade -y

echo "Running apt autoremove and clean..."
apt-get autoremove -y
apt-get clean

echo "Restarting services affected by upgrades (if any)..."
/usr/sbin/needrestart -r a

echo "Checking for eeprom updates..."
if rpi-eeprom-update | grep -q "UPDATE AVAILABLE"; then
    rpi-eeprom-update -a
    echo "EEPROM update initiated. Will apply on next reboot."
else
    echo "No eeprom update required."
fi

echo "Maintenance complete."