# Wormhole 
VPN server installer for Raspberry Pi.

## 1. Client

The installer itself. Uses official Raspberry Pi imager **rpi-imager** tool to download and write the OS iso to your media. Simplifies configuration for the client by moving most of the decision making to the owner of the API server. Runs in CLI.

### Hardware: 

Linux machine with a SD-card-reader. or SATA/NVMe reader. Can be the same computer as the server.

### Software: 

**wormhole-installer** bash script

## 2. Server
- Serves configurations to the installer clients
- Monitors the intallation process
- Monitors existing Raspberry Pi nodes

### Hardware:

Anything that runs docker

### Software:

**Node-RED** flow


## 3. Node
- Runs the Wireguard VPN server and other services as docker containers
- Reports to the server

### Hardware: 

**Raspberry Pi**

Tested on RPi 4B

### Software:

- **wormholed.service** systemd service

- **wormholeinstallerd.service** systemd service - Installs everything else and disables itself in the end. Logs the installation process to both client and server.

- Docker stacks and containers: 
    - vpn
        - pihole
        - unbound
        - wireguard
    - network:
        - NGINX Proxy Manager
    - supervisor:
        - dockge
        - uptime kuma
    - iot
        - nodered
    - storage
        - syncthing

# Installation

### Client:
1. Pick a directory to store wormhole-installer and cd into it:

```
mkdir ~/wormhole-installer
cd ~/wormhole-installer
```

2. Get your token and crypto key from the server. Along with server's url they will be stored in ~/.bashrc.
Download and install wormhole-installer, run the following command:

```
curl -f -s -o install.sh -H "Authorization: Bearer <TOKEN>" <URL>/wh/install && bash install.sh <URL>/wh/install <TOKEN> <CRYPTO_KEY>
```

3. Connect the SD card or any installation media.

4. From any directory, run:

```
wormhole-installer
```

To update to the version currently on the server:

```
wormhole-installer --update
```

Show options:

```
wormhole-installer --help
```

### Server:

1. Clone the repository.
2. Spin up a [Node-RED container](https://nodered.org/docs/getting-started/docker)
3. Add the Wormhole flow to Node-RED instance
4. Set up environment variables in the flow.
5. Deploy the flow.

### Node:
1. Power on
2. Wait

# Uninstallation

### Client:
Run:
```
wormhole-installer --uninstall
```

Alternatively, cd into install directory and run:
```
./uninstall.sh
```

### Server:
Disable or delete the Node-RED flow

# Motivation
Primary goal is simpifying the OS flashing and first setup for the user on the client side by offloading most of the decisions to the user on the server side. Client's installation script is designerd to be simple and interactive, provide detailed instructions and progress status. It also reports progress to the server to simplify support and troubleshooting.


# TODOs:

wormhole tool
- backup and restore
    - run backup or restore over one or all docker stacks
        - stop stack
        - run backups/restores
        - run stack
- sync backup folder to other hosts

wormholed.sh
- auto-updates
    - system updates (nfs, ssh, etc.)
    - wormhole updates
- help

server:
- create api-keys and example config file from node-red if they are not present

docker setup:
- DNS troubleshooting

wormholeinstalld.sh:
- fix progress bar stages
- restore docker volumes from backup
- ufw

wormhole-installer:
- fix incorrect network interface being picked when pi is on both eth and wifi
- mc theme setter fix

refactoring:
- duplicated variables