#!/bin/bash

# ==============================================================================
# This script updates the WORMHOLE client by downloading the latest
# version and its checksum from the configured API endpoint.
#
# It performs the following steps:
# 1. Verifies that the necessary environment variables, WORMHOLE_API_KEY,
#    WORMHOLE_API_URL and WORMHOLE_CRYPTO_KEY are set.
# 2. Downloads the latest install script and a gzipped tar archive of the
#    application.
# 3. Downloads the SHA256 checksum from the server and validates the integrity
#    of the downloaded archive.
# 4. Extracts the contents of the archive and cleans up the temporary file.
# 5. Dispalys the updated version.
#
# Prerequisites:
# - The WORMHOLE_API_KEY, WORMHOLE_API_URL, WORMHOLE_CRYPTO_KEY environment
#   variables must be set in the user's environment.
#
# ==============================================================================


# Configuration
binary_name="wormhole-installer"
symlink_path="/usr/local/bin/${binary_name}"
endpoint_install="/wh/install"
api_domain=${WORMHOLE_API_URL}
install_url="${WORMHOLE_API_URL}${endpoint_install}"
distro_url="${install_url}.distro"
sha_url="${install_url}.sha256"
key_derivation="-pbkdf2"
crypto_cipher="-aes-256-cbc"

INSTALL_MODE=0
while getopts "i" opt; do
    case ${opt} in
        i )
            INSTALL_MODE=1
            ;;
        \? )
            echo "Usage: $0 [-i]" >&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Base Directory Resolution
if [ "$INSTALL_MODE" -eq 1 ]; then
    SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do
        DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    base_dir="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
else
    if [ -L "$symlink_path" ]; then
        target_path=$(readlink -f "$symlink_path")
        base_dir=$(dirname "$target_path")
        echo "Found the installation in ${base_dir}"
    else
        echo "Error: Application not found via symlink ${symlink_path}*."
        exit 1
    fi
fi

if [ -z "$WORMHOLE_API_KEY" ] || [ -z "$WORMHOLE_API_URL" ] || [ -z "$WORMHOLE_CRYPTO_KEY" ]; then
    echo "Error: One or both of the environment variables (WORMHOLE_API_KEY, WORMHOLE_API_URL, WORMHOLE_CRYPTO_KEY) are missing." >&2
    exit 1
fi

echo "Updating the application from ${api_domain}..."

# Updates the install script and triggers the repacking of the tar to the latest live version
response=$(curl -f -s -o "${base_dir}/install.sh" -H "Authorization: Bearer ${WORMHOLE_API_KEY}" -w "%{http_code}" "${install_url}")
if [ $response -ne 200 ]; then
    echo "Error: Server response $response"
    exit 1
fi

new_distro_dir=$(mktemp -d)
trap 'rm -rf "$new_distro_dir"' EXIT
new_distro_tar="$(mktemp "${new_distro_dir}/wh-update.XXXXXXXXX.tar")"
new_distro_tar_enc="$(mktemp "${new_distro_dir}/wh-update.XXXXXXXXX.tar.enc")"

echo "Downloading tar archive..."
curl -s -f -o ${new_distro_tar_enc} -H "Authorization: Bearer ${WORMHOLE_API_KEY}" "${distro_url}"

echo "Decrypting archive..."
openssl enc -d ${crypto_cipher} ${key_derivation} -in ${new_distro_tar_enc} -out ${new_distro_tar} -k "$WORMHOLE_CRYPTO_KEY"

echo "Requesting the SHA256 checksum..."
sha256=$(curl -s -f "${sha_url}")

if [[ "$(sha256sum "${new_distro_tar}" | awk '{print $1}')" == "${sha256}" ]]; then
    echo "SHA256 checksum is valid. The package is intact."
else
    echo "SHA256 checksum mismatch! The file may be corrupt."
    exit 1
fi

echo "Unpacking..."
tar -xf ${new_distro_tar} -C "${base_dir}"
if [[ $? -ne 0 ]]; then
    echo "Error when unpacking tar"
    exit 1
fi

echo "Creating symlink in /usr/local/bin"
sudo ln -sf ${base_dir}/start.sh "${symlink_path}"

source ${base_dir}/res/theme.env

new_version=$(${base_dir}/start.sh -V)
echo -e "${T_GREEN}Updated to ${new_version}${T_NC}"
if [ "$INSTALL_MODE" -eq 1 ]; then
    echo -e "To start the installer, run ${T_BLUE}${binary_name}${T_NC}"
fi