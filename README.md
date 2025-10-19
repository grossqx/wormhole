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

2. Get a running Node-RED instance. If you already have Node-RED, you can skip this step.

    Recommended way is as a [docker compose](https://docs.docker.com/compose/) project. You can follow the instuctions [here](https://github.com/node-red/node-red-docker/blob/master/README.md) or use this repo's provided docker-compose  file.

3. Add the Wormhole flow to Node-RED instance
    

    Hamburger menu -> Import -> Paste flow json or select and import the provided file

4. Customize environment variables in the flow.

    To get to the environment variable editor in Node-RED GUI, double-click the flow's tab name -> Environment Variables (button).
    
    Alternatively, environment variables can be edited in the flow itself json before importing it. They are in the 'env' section.

5. Deploy the flow.

### Node:
1. Connect the storage device with an image written by the **wormhole-installer** to the Raspberry Pi. 
2. If Rapsbery Pi was previously configured to boot from a different device type, physically disconnect those storage devices or change the boot order beforehand. They can be reconnected once the installer on the Pi passes the first stage.
3. Wait

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

docker setup:
- DNS troubleshooting

wormholed.sh
- auto-updates
    - system updates (nfs, ssh, etc.)
    - wormhole updates
- detect new drives as migration cadidates
- help

wormhole tool
- sync backup folder to other hosts

server:
- create api-keys and example config file from node-red if they are not present

wormholeinstalld.sh:
- fix progress bar stages
- restore docker volumes from backup
- ufw

wormhole-installer:
- fix incorrect network interface being picked when pi is on both eth and wifi
- mc theme setter fix
- make inputs invisible for ssh password and wifi password when inputting from keyboard

## Licenses for other components
- Node-RED [Apache 2.0](https://github.com/node-red/node-red/blob/master/LICENSE)
- rpi-clone [BSD 3-Clause](https://github.com/geerlingguy/rpi-clone/blob/master/LICENSE)
- rpi-imager [LGPL v3](https://github.com/raspberrypi/rpi-imager/blob/main/license.txt)
- Docker: [Apache 2.0](https://github.com/docker/docker/blob/master/LICENSE)
- WireGuard [GPL v2](https://www.wireguard.com/#license)
- Pi-hole [EUPL v1.2](https://github.com/pi-hole/pi-hole/blob/master/LICENSE)
- Unbound: [BSD License](https://unbound.nlnetlabs.nl/svn/trunk/LICENSE)