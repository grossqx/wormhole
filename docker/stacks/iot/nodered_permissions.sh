#!/bin/bash
#
# Resolve nodered permissions

nodered_data_path=${STORAGE_PATH}/node-red/data

echo "Setting permissions for NodeRED directory ${nodered_data_path}"
mkdir -p ${nodered_data_path}
sudo chown -R "$(id -u wormhole):$(id -g wormhole)" ${nodered_data_path}
chmod -R 755 ${nodered_data_path}