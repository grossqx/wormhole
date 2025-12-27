#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <SSH_PORT> <WIREGUARD_PORT>"
    echo "Example: $0 22 51820"
    exit 1
fi

SSH_PORT=$1
WG_PORT=$2

echo "Installing UFW..."
apt-get update
apt-get install -y ufw

echo "Configuring UFW for Docker compatibility..."
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

echo "Applying firewall rules..."
ufw --force reset

ufw default deny incoming
ufw default allow outgoing

ufw allow $SSH_PORT/tcp comment 'Allow SSH for administration'
ufw allow $WG_PORT/udp comment 'Allow WireGuard VPN connections'

echo "Enabling firewall..."
ufw enable

echo "UFW configuration complete. Status:"
ufw status verbose