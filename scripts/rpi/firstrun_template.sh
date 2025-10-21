#!/bin/bash

## This is a script that should only run on a Raspberry Pi.
## Runs once, on first boot and is triggered by the kernel parameter in cmdline.txt
## In the end of this script, it deletes itself.


## ===============================================================================================================
## [WH] Needed to extract files embedded by customize_firstrun.sh
## ===============================================================================================================
function extract_embedded_file_simple() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: extract_file_simple <name>"
        return 1
    fi
    local start_line=$(grep -m 1 -n "^___START_FILE_CONTENT___${name}___" "$0" | cut -d: -f1)
    if [[ -z "$start_line" ]]; then
        echo "Error: Start line for ${name} not found in $0"
        return 1
    fi
    local file_path_literal=$(sed -n "${start_line}s/^___START_FILE_CONTENT___${name}___\(.*\)___$/\1/p" "$0")
    if [[ -z "$file_path_literal" ]]; then
        echo "Error: Extract file for ${name} path not found in $0"
        return 1
    fi
    local file_path=$(eval echo "$file_path_literal")
    local end_line=$(awk "NR > $start_line && /^EOF$/ {print NR; exit}" "$0")
    if [[ -z "$end_line" ]]; then
        echo "Error: EOF for ${name} not found in $0"
        return 1
    fi
    mkdir -p "$(dirname "$file_path")"
    sed -n "$(($start_line + 1)),$(($end_line - 1))p" "$0" > "$file_path"
    chmod +x "${file_path}"
    echo "Extracted '${file_path}'"
}
## ===============================================================================================================

## ===============================================================================================================
## [WH] Logging function specific for firstrun.sh
## ===============================================================================================================
function log() {
    local message=$(cat -)
    if [ -n "$message" ]; then
        echo "$message" | tee -a "$firstrun_log_path"
        # Check for internet connection with a ping test
        if ping -c 1 "${connectivity_test_host}" > /dev/null 2>&1; then
            if [ -f "${install_log_script}" ]; then
                "${install_log_script}" "${install_log_endpoint}" "${WH_INSTALL_ID}" "$message"
                sleep 0.2
            fi
        fi
    fi
}
## ===============================================================================================================


## ===============================================================================================================
## [WH] These variables are filled out by the installer script.
## ===============================================================================================================
HOSTNAME=""
TIMEZONE=""
WIFI_SSID=""
WIFI_PASS=""
WIFI_LOC=""
SSH_USER=""
SSH_PASS=""
SSH_PORT=""


## ===============================================================================================================
## [WH] These variables are filled out by the installer script and kept on the Pi.
## ===============================================================================================================
WH_INSTALL_ID=""
WH_INSTALL_CONFIG=""
WH_INSTALL_USER=""
WH_INSTALL_USER_IP=""
WH_SERVER_API_URL=""
WH_HARDWARE_API_KEY=""
WH_CRYPTO_DERIVATION=""
WH_CRYPTO_CIPHER=""
WH_CRYPTO_KEY=""
WH_IP_ADDR=""
WH_DOMAIN=""
WH_WIREGUARD_PORT=""
WH_PATH=""
WH_BOOT_DEVICE=""
WH_BOOT_DEVICE2=""

## ===============================================================================================================
## [WH] Constant variables
## ===============================================================================================================
binary_name="wormhole"
connectivity_test_host="8.8.8.8"
firstrun_log_path="/boot/firstrun.log"
library_dir="/etc/profile.d"
wormhole_home_path="/home/wormhole"
systemd_service_dir="/etc/systemd/system"
wormhole_uid=950
wormhole_gid=950
wormhole_groups="gpio,i2c,spi"
## ===============================================================================================================


## ===============================================================================================================
## [WH] Other variables
## ===============================================================================================================
installer_dir="${WH_PATH}/installer"
install_log_endpoint="${WH_SERVER_API_URL}/wh/install_log_write"
install_log_script="${installer_dir}/report_install_progress.sh"
firstrun_backup="/home/firstrun_backup.sh"
wormhole_install_log_path="${wormhole_home_path}/wormhole_install.log"
symlink_path="/usr/bin/${binary_name}"
wormhole_log_path="/var/log/wormhole.log"
## ===============================================================================================================


## ===============================================================================================================
## [Required for firstrun.sh to function!] Continue on error
## ===============================================================================================================
set +e
## ===============================================================================================================


## ===============================================================================================================
## At this point:
## pwd will return "/"
## $HOME will return an empty string
## ===============================================================================================================
journalctl -b | grep -E "systemd.run" | while read -r line; do
    echo "[first boot] $line" | log
done
echo "[1/17] firstrun.sh Starting" | log
echo "Backed up to ${firstrun_backup}" | log
cat "$0" >> "$firstrun_backup" | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Adding permanent environment variables
## ===============================================================================================================
echo "[2/17] Adding permanent environment variables to /etc/environment." | log
cat << EOF | sudo tee -a /etc/environment
# --- Wormhole variables ---
WH_INSTALL_ID="${WH_INSTALL_ID}"
WH_INSTALL_CONFIG="${WH_INSTALL_CONFIG}"
WH_INSTALL_USER="${WH_INSTALL_USER}"
WH_INSTALL_USER_IP="${WH_INSTALL_USER_IP}"
WH_SERVER_API_URL="${WH_SERVER_API_URL}"
WH_HARDWARE_API_KEY="${WH_HARDWARE_API_KEY}"
WH_CRYPTO_DERIVATION="${WH_CRYPTO_DERIVATION}"
WH_CRYPTO_CIPHER="${WH_CRYPTO_CIPHER}"
WH_CRYPTO_KEY="${WH_CRYPTO_KEY}"
WH_IP_ADDR="${WH_IP_ADDR}"
WH_DOMAIN="${WH_DOMAIN}"
WH_WIREGUARD_PORT="${WH_WIREGUARD_PORT}"
WH_PATH="${WH_PATH}"
WH_HOME="${wormhole_home_path}"
WH_LOG_FILE="${wormhole_log_path}"
WH_BOOT_DEVICE="${WH_BOOT_DEVICE}"
WH_BOOT_DEVICE2="${WH_BOOT_DEVICE2}"
# --------------------------
EOF
## ===============================================================================================================


## ===============================================================================================================
## [WH] Exporting embedded scripts
## ===============================================================================================================
echo "[3/17] Extracting embedded scripts" | log
extract_embedded_file_simple "embed_extract_files" 2>&1 | log
source "${installer_dir}/embed_extract_files.sh" >/dev/null 2>&1

extract_file "read_install_progress" 2>&1 | log
extract_file "report_install_progress" 2>&1 | log
install_log_script=$(get_file_unpack_path "$0" "report_install_progress" 2> >(log))

echo "[4/17] Extracting wormhole libraries..." | log
extract_file "rpi_sysinfo" 2>&1 | log
extract_file "wh_logger" 2>&1 | log
extract_file "wh_storage" 2>&1 | log
rpi_sysinfo_script=$(get_file_unpack_path "$0" "rpi_sysinfo" 2> >(log))

echo "[5/17] Extracting embedded services" | log

service_file_name="wormholed.service"
echo "Installing ${service_file_name}..." | log
service_exec_file=$(get_file_unpack_path "$0" "wormholed" 2> >(log))
service_unit_file=$(get_file_unpack_path "$0" "wormholed-service" 2> >(log))
extract_file "wormholed" 2>&1 | log
extract_systemd_service "wormholed-service" "${service_exec_file}" "${service_unit_file}" 2>&1 | log

service_file_name="wormholeinstalld.service"
echo "Installing ${service_file_name}..." | log
service_exec_file=$(get_file_unpack_path "$0" "wormholeinstalld" 2> >(log))
service_unit_file=$(get_file_unpack_path "$0" "wormholeinstalld-service" 2> >(log))
extract_file "wormholeinstalld" 2>&1 | log
extract_systemd_service "wormholeinstalld-service" "${service_exec_file}" "${service_unit_file}" 2>&1 | log
echo "Enabling ${service_file_name}" | log
systemctl enable "${service_file_name}" | log

echo "[6/17] Extracting wormhole main scripts..." | log
extract_file "wormhole" 2>&1 | log
extract_file "update" 2>&1 | log
extract_file "system_update" 2>&1 | log
extract_file "config_update" 2>&1 | log

echo "[7/17] Creating a symlink at ${symlink_path}." | log
main_binary_file=$(get_file_unpack_path "$0" "wormhole" 2> >(log))
main_binary_path=$(eval echo "$main_binary_file")
ln -s "${main_binary_path}" "${symlink_path}" | log

echo "[8/17] Extracting wormhole helper scripts..." | log
extract_file "initial_update" 2>&1 | log
extract_file "benchmark" 2>&1 | log
extract_file "docker_install" 2>&1 | log
extract_file "docker_update_config" 2>&1 | log
extract_file "docker_update_env" 2>&1 | log
extract_file "docker_manage" 2>&1 | log
extract_file "docker_backups" 2>&1 | log
extract_file "ufw_config" 2>&1 | log
extract_file "nfs_config" 2>&1 | log
extract_file "git_install" 2>&1 | log
extract_file "git_clone_repo" 2>&1 | log
extract_file "set_boot_order" 2>&1 | log
extract_file "migration" 2>&1 | log
extract_file "mc_set_theme" 2>&1 | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Set hostname 
## ===============================================================================================================
echo "[9/17] Setting hostname" | log
sudo hostnamectl set-hostname "${HOSTNAME}" | log
sudo sed -i "s/127.0.1.1.*$/127.0.1.1\t\t${HOSTNAME}/" "/etc/hosts" | log
cat /etc/hosts | grep "${HOSTNAME}" | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Set ssh port
## ===============================================================================================================
echo "[10/17] Setting ssh port" | log
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
echo "Configuration backed up to /etc/ssh/sshd_config.bak" | log
sudo sed -i "s/#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config
systemctl enable ssh
echo "ssh enabled - $(cat /etc/ssh/sshd_config | grep 'Port ')" | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Setting up the user
## ===============================================================================================================
echo "[11/17] Setting up the configured user" | log
echo "Adding user ${SSH_USER}" | log
sudo useradd -m \
    -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,render,netdev,gpio,i2c,spi \
    -u 1001 ${SSH_USER}
echo "user id:" | log
id ${SSH_USER} | log
echo "user groups:" | log
groups ${SSH_USER} | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Setting user's password
## ===============================================================================================================
echo "[12/17] Setting user's password" | log
echo "${SSH_USER}:${SSH_PASS}" | sudo chpasswd
echo "Username and password updated" | log
passwd --status ${SSH_USER} | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Setting up the wormhole service user
## ===============================================================================================================
# --system: creates a system user with a UID
# --no-create-home: prevents a home directory, as it's not needed for a service
# --shell /usr/sbin/nologin: prevents interactive shell login for security
# --gid: sets the primary group to 'wormhole'
# --groups: adds secondary group memberships
echo "[13/17] Setting up the wormhole user" | log
echo "Creating dedicated system group 'wormhole'" | log
sudo groupadd --system --gid "$wormhole_gid" wormhole | log
echo "Adding dedicated system user 'wormhole'" | log
sudo useradd --system \
    --uid "$wormhole_uid" \
    --gid "$wormhole_gid" \
    --home-dir "${wormhole_home_path}" \
    --shell /usr/sbin/nologin \
    --groups "$wormhole_groups" \
    wormhole | log
echo "user id:" | log
id wormhole | log
echo "user groups:" | log
groups wormhole | log
echo "Setting /etc/nologin.txt message" | log
echo "I'm sorry, Dave. I'm afraid I can't do that." | tee /etc/nologin.txt
## ===============================================================================================================


## ===============================================================================================================
## [WH] Deleting default user
## ===============================================================================================================
echo "[14/17] Deleting default user 'pi'" | log
sudo userdel -r pi | log
echo "pi user is no more" | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Set the timezone
## ===============================================================================================================
echo "[15/17] Setting the timezone" | log
sudo raspi-config nonint do_change_timezone "${TIMEZONE}"
echo "Timezone set to ${TIMEZONE}" | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Set WiFi settings
## ===============================================================================================================
echo "[16/17] Setting WiFi SSID and password" | log
/usr/lib/raspberrypi-sys-mods/imager_custom \
    set_wlan "${WIFI_SSID}" "${WIFI_PASS}" "${WIFI_LOC}"
echo "Wifi SSID set to ${WIFI_SSID}. Password set to <hidden>" | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Get baseline system info
## ===============================================================================================================
echo "Starting system information:" | log
source "$rpi_sysinfo_script"
rpi-sysinfo | while read -r line; do
    echo "$line" | log
done
## ===============================================================================================================


## ===============================================================================================================
## [Required for firstrun.sh to function!] Self-destruct
## ===============================================================================================================
## Remove the firstrun.sh and the systemd directive to re-run it.
echo "[17/17] firstrun.sh Finished. The script will now delete itself and reboot the RPi." | log
## ===============================================================================================================


## ===============================================================================================================
## [WH] Copy the log file to home directory
## ===============================================================================================================
echo "Creating a log file at ${wormhole_install_log_path}" | log
mkdir -p "${wormhole_home_path}"
cp "${firstrun_log_path}" "${wormhole_install_log_path}" | log
## ===============================================================================================================


## ===============================================================================================================
## ===============================================================================================================
rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt
exit 0
## ===============================================================================================================
## ===============================================================================================================
## Reboot will be perfomed immediately after