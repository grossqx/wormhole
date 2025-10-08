# Wormhole 
Raspberry Pi VPN server installer

## TODOs:

wormhole-installer:
- fix incorrect network interface being picked when pi is on both eth and wifi

wormholeinstalld.sh:
- backup and restore docker storage
- add migration to install process
- nfs server (userful.sh)
- ufw
- memory test
- add wh_log throughout the main script
    
server:
- create api-keys and example config file from node-red if they are not present


## Components:

### Server
- Serves configurations to the installer clients
- Monitors the intallation process
- Monitors existing Raspberry Pi nodes

Software: **Node-RED** flow

Hardware: Anything that runs docker

### Client
- Uses official Raspberry Pi imager **rpi-imager** tool to download and write the OS iso to your media.
- Simplifies configuration for the client by moving most of the decision making to the owner of the API server.
- Can be the same computer as the server

Software: **wormhole-installer** bash script

### Raspberry Pi
- Runs the Wireguard VPN server and other services as docker containers
- Reports to the server

Software:
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

- **wormholeinstallerd.service** systemd service - Installs everything else and disables itself in the end. Logs the installation process to both client and server.

- **wormholed.service** systemd service


## Installation

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

1. Pull or clone the repository.
2. Spin up a Node-RED container
https://nodered.org/docs/getting-started/docker
3. Add the Wormhole flow to Node-RED instance
4. Set up environment variables in the flow.
5. Deploy the flow.


## Uninstallation


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

## Motivation
Made for personal use. Primary goal is simpifying the OS flashing and first setup for the user on the client side by offloading most of the decisions to the user on the server side. Client's installation script is designerd to be simple and interactive, provide detailed instructions and progress status. It also reports progress to the server to simplify support.