#!/bin/bash

echo "Checking filesystem:"
lsblk -f -o LABEL,PATH,NAME,FSAVAIL,FSUSED,FSTYPE,FSVER,VENDOR,MOUNTPOINTS,UUID
echo

echo "Checking updates:"
sudo apt update
echo

echo "Upgradable apps:"
apt list --upgradable
echo

echo "Running full upgrade:"
sudo apt-get -o Dpkg::Options::="--force-confnew" --assume-yes full-upgrade -y
echo

echo "Running apt autoremove:"
sudo apt autoremove -y

echo "Before apt clean:"
lsblk -f -o LABEL,PATH,NAME,FSAVAIL,FSUSED,FSTYPE,FSVER,VENDOR,MOUNTPOINTS,UUID
echo

sudo apt clean

echo "After apt clean:"
lsblk -f -o LABEL,PATH,NAME,FSAVAIL,FSUSED,FSTYPE,FSVER,VENDOR,MOUNTPOINTS,UUID
echo

# Outputs the current bootloader configuration to STDOUT if no arguments are specified
echo "Current bootloader configuration:"
rpi-eeprom-config
echo

# Check eeprom update
echo "Checking for eeprom update:"
sudo rpi-eeprom-update
echo

sudo rpi-eeprom-update | grep "UPDATE AVAILABLE"
result=$?
if [[ $result -eq 0 ]]; then
    # Schedule eeprom update
    sudo rpi-eeprom-update -a
    echo "eeprom update initiated"
else
    echo "no eeprom update required"
fi