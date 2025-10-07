#!/bin/bash

cleanup_packages="docker.io docker-doc docker-compose podman-docker containerd runc"
install_packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

echo "Starting docker install..."

echo "[1/8] Removing old packages"
sudo apt-get remove -y $cleanup_packages || true

echo "[2/8] Pre-update..."
sudo apt-get update -y

echo "[3/8] Installing Docker's official GPG key..."
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "[4/8] Adding Docker repository to Apt sources..."

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[5/8] Re-update..."
sudo apt-get update -y

echo "[6/8] Installing docker packages..."

sudo apt-get install -y $install_packages

echo "[7/8] Docker install done!"
docker --version

if ! getent group docker > /dev/null; then
  echo "The 'docker' group does not exist."
fi

for user in $(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1}'); do
  echo "Adding user '$user' to the 'docker' group..."
  sudo usermod -aG docker "$user"
  groups $user
done

sudo usermod -aG docker "wormhole"
groups wormhole

echo "[8/8] Docker setup finished"