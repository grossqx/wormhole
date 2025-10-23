# Wormhole 
VPN server installer for Raspberry Pi.

## 1. Client

**wormhole-installer** bash script uses official Raspberry Pi **rpi-imager** tool to download and write the OS image to your media. Runs in CLI. 
Simplifies installation by moving most of the decision making to the admin of wormhole **server**. Pulls pre-made user-specific configurations from the **server**. Utilizes *image customization* feature to pack the **wormhole** configuration, scripts and services into *firstrun.sh*. Provides the client with router configuration insructions.
Displays progress and a realtime log of the **wormhole** installer finalizing setup on the **node** itself after it was powered on.

### Hardware: 

Linux machine with a SD-card-reader. or SATA/NVMe reader. *Can also be the same computer as the server.*


## 2. Server

Powered by **Node-RED** and defined by a single *flow.json* file.

- Authentication for **clients** and **nodes**
- Defines and serves **node configurations** to the installer **clients**
- Serves configuration updates to the live **nodes**
- Monitors system state of existing Raspberry Pi **nodes**
- Handles logging

## 3. Node

**wormhole** - Management Utility bash script. Handles administrative functions and provides commands to manually manage docker stacks and environment, backups, updates, migration and configuration changes.

**wormholeinstalld.service** - Installs everything else and disables itself in the end. Logs the installation process to both client and server.

**wormholed.service** - Main background daemon. Handles telemetry reporting to the server and manages routine checks on every reboot.

### Hardware: 

**Raspberry Pi** 

*Tested on: Raspberry Pi 4B*

### Docker stacks and services:
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

# Issues:

Feel free to open an issue if you found a bug or have an improvement suggestion.
## Known upsteam issues:
[[BUG]: rpi-imager ignores settings in firstrun.sh when writing to nvme](https://github.com/raspberrypi/rpi-imager/issues/1165)

# Acknowledgments

Server running on [Node-RED](https://github.com/node-red/node-red-docker).

Docker-compose project for the node is based on [wirehole](https://github.com/IAmStoxe/wirehole) project. Main functionality provided by:
- [WireGuard](https://www.wireguard.com/) (image [linuxserver/wireguard](https://docs.linuxserver.io/images/docker-wireguard/))
- [Unbound](https://unbound.nlnetlabs.nl/)
- [Pi-hole](https://github.com/pi-hole/pi-hole)

Installer makes use of the official [Raspberry Pi Imager](https://github.com/raspberrypi/rpi-imager).

Migration powered by [rpi-clone](https://github.com/geerlingguy/rpi-clone).


# Licenses for other components
- Node-RED   [Apache 2.0](https://github.com/node-red/node-red/blob/master/LICENSE)
- rpi-clone  [BSD 3-Clause](https://github.com/geerlingguy/rpi-clone/blob/master/LICENSE)
- rpi-imager [LGPL v3](https://github.com/raspberrypi/rpi-imager/blob/main/license.txt)
- Docker:    [Apache 2.0](https://github.com/docker/docker/blob/master/LICENSE)
- WireGuard  [GPL v2](https://www.wireguard.com/#license)
- Pi-hole    [EUPL v1.2](https://github.com/pi-hole/pi-hole/blob/master/LICENSE)
- Unbound:   [BSD License](https://unbound.nlnetlabs.nl/svn/trunk/LICENSE)
