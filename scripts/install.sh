#!/bin/bash

# ==============================================================================
# This script installs or updates the WORMHOLE client by downloading the latest
# version from the specified API URL.
#
# It also configures the WORMHOLE_API_KEY, WORMHOLE_API_URL amd WORMHOLE_CRYPTO_KEY 
# environment variables in ~/.bashrc.
#
# The script takes two optional arguments:
# 1. API URL (URL): The base URL for the WORMHOLE API.
# 2. API Key (TOKEN): The authorization token for the WORMHOLE API.
# 3. Crypto key
#
# If a new value is provided for both variables, it updates the corresponding
# lines in ~/.bashrc or adds it if it's not present. If an argument is not
# provided, the script will use the existing environment variable from ~/.bashrc.
#
# ==============================================================================

URL="$1"
TOKEN="$2"
CRYPTO_KEY="$3"

endpoint_install="/wh/install"
endpoint_update="/wh/install.update"
api_domain="${URL%${endpoint_install}}"
install_from_server_command="curl -f -s -o install.sh -H \"Authorization: Bearer <TOKEN>\" \"<URL>/wh/install\""

if [ "$(ls -A . | grep -v "$(basename "${BASH_SOURCE[0]}")")" ]; then
    echo "Warning: The current directory $(pwd) is not empty. Proceeding may overwrite existing files."
    echo "This script is designed to download and unpack files, and it's best to run it"
    echo "in a dedicated, empty directory to avoid overwriting or mixing files."
    read -p "Are you sure you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled. Exiting."
        exit 1
    fi
fi

if [[ -z "$TOKEN" || -z "$api_domain" || -z "$CRYPTO_KEY" ]]; then
    if [ -f "./update.sh" ]; then
        echo "Existing install found."
        echo "To update it to the latest version:"
        echo "  Option 1 - run: ./update.sh"
        echo "  Option 2 - run: ${install_from_server_command}"
        echo "To change the server URL and API key configured before and and update:"
        echo "  Option 1 - run: ./install.sh <URL> <TOKEN> <CRYPTO_KEY>"
        echo "  Option 2 - manually edit: ~/.bashrc and restart the terminal"
        exit 1
    fi
fi

if [ -n "$TOKEN" ]; then
    if grep -q "export WORMHOLE_API_KEY=" ~/.bashrc; then
        echo "Found existing WORMHOLE_API_KEY in ~/.bashrc. Updating its value."
        sed -i.bak -E "s|^(export WORMHOLE_API_KEY=).*$|export WORMHOLE_API_KEY='${TOKEN}'|" ~/.bashrc
    else
        echo "WORMHOLE_API_KEY will be stored in ~/.bashrc."
        echo "export WORMHOLE_API_KEY='${TOKEN}'" >> ~/.bashrc
    fi
else
    echo "No API key provided as arg. Using environment variable."
fi

if [ -n "$api_domain" ]; then
    if grep -q "export WORMHOLE_API_URL=" ~/.bashrc; then
        echo "Found existing WORMHOLE_API_URL in ~/.bashrc. Updating its value."
        sed -i.bak -E "s|^(export WORMHOLE_API_URL=).*$|export WORMHOLE_API_URL='${api_domain}'|" ~/.bashrc
    else
        echo "WORMHOLE_API_URL will be stored in ~/.bashrc."
        echo "export WORMHOLE_API_URL='${api_domain}'" >> ~/.bashrc
    fi
else
    echo "No API URL provided as arg. Using environment variable."
fi

if [ -n "$CRYPTO_KEY" ]; then
    if grep -q "export WORMHOLE_CRYPTO_KEY=" ~/.bashrc; then
        echo "Found existing WORMHOLE_CRYPTO_KEY in ~/.bashrc. Updating its value."
        sed -i.bak -E "s|^(export WORMHOLE_CRYPTO_KEY=).*$|export WORMHOLE_CRYPTO_KEY='${CRYPTO_KEY}'|" ~/.bashrc
    else
        echo "WORMHOLE_CRYPTO_KEY will be stored in ~/.bashrc."
        echo "export WORMHOLE_CRYPTO_KEY='${CRYPTO_KEY}'" >> ~/.bashrc
    fi
else
    echo "No crypto key provided as arg. Using environment variable."
fi

source $HOME/.bashrc

if [ -z "$WORMHOLE_API_KEY" ] || [ -z "$WORMHOLE_API_URL" ] || [ -z "$WORMHOLE_CRYPTO_KEY" ]; then
    echo "Error: One of the environment variables (WORMHOLE_API_KEY, WORMHOLE_API_URL, WORMHOLE_CRYPTO_KEY) are missing after sourcing ~/.bashrc." >&2
    exit 1
fi

update_url="${WORMHOLE_API_URL}${endpoint_update}"

response=$(curl -f -s -o update.sh -H "Authorization: Bearer ${WORMHOLE_API_KEY}" -w "%{http_code}" "${update_url}")
if [ $response -ne 200 ]; then
    echo "Error: Failed to download update.sh. Server response $response"
    exit 1
fi

chmod +x ./update.sh
./update.sh -i