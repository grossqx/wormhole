#!/bin/bash

# ==============================================================================
# This script updates the app by downloading the latest
# version and its checksum from the configured API endpoint.
#
# It performs the following steps:
# 1. Verifies that the necessary environment variables, WH_HARDWARE_API_KEY,
#    WH_SERVER_API_URL, WH_CRYPTO_KEY are set.
# 2. Downloads the latest install script and a gzipped tar archive of the
#    application.
# 3. Downloads the SHA256 checksum from the server and validates the integrity
#    of the downloaded archive.
# 4. Extracts the contents of the archive and cleans up the temporary files.
#
# Prerequisites:
# - The WH_HARDWARE_API_KEY, WH_SERVER_API_URL, WH_CRYPTO_KEY environment 
#   variables must be set in the user's environment.
#
# ==============================================================================
set -e

if [ -z "$WH_HARDWARE_API_KEY" ] || [ -z "$WH_SERVER_API_URL" ] || [ -z "$WH_CRYPTO_KEY" ] || [ -z "$WH_CRYPTO_CIPHER" ] || [ -z "$WH_CRYPTO_DERIVATION" ]; then
    echo "Error: One of the environment variables (WH_HARDWARE_API_KEY, WH_SERVER_API_URL, WH_CRYPTO_KEY, WH_CRYPTO_CIPHER, WH_CRYPTO_DERIVATION) are missing." >&2
    exit 1
fi

endpoint_update="/wh/rpi.update"
endpoint_encryption="/wh/encryption_parms_rpi"
api_domain=${WH_SERVER_API_URL}
distro_url="${WH_SERVER_API_URL}${endpoint_update}"
encryption_url="${WH_SERVER_API_URL}${endpoint_encryption}"

sha_url="${distro_url}.sha256"

echo "Updating the application from ${api_domain}..."

echo "Checking current version..."
encryption_parms=$(curl -s -f -H "Authorization: Bearer ${WH_HARDWARE_API_KEY}" "${encryption_url}")
script_version=$(echo $encryption_parms | awk {'print $3'})

new_distro_dir=$(mktemp -d)
trap 'rm -rf "$new_distro_dir"' EXIT
new_distro_tar="$(mktemp "${new_distro_dir}/wh-update.XXXXXXXXX.tar")"
new_distro_tar_enc="$(mktemp "${new_distro_dir}/wh-update.XXXXXXXXX.tar.enc")"

echo "Downloading tar archive..."
response=$(curl -s -f -o ${new_distro_tar_enc} -H "Authorization: Bearer ${WH_HARDWARE_API_KEY}" -w "%{http_code}" "${distro_url}")
if [ $response -ne 200 ]; then
    echo "Error: Server response $response"
    exit 1
fi

echo "Decrypting archive..."
openssl enc -d ${WH_CRYPTO_CIPHER} ${WH_CRYPTO_DERIVATION} -in ${new_distro_tar_enc} -out ${new_distro_tar} -k "$WH_CRYPTO_KEY"

echo "Requesting the SHA256 checksum..."
sha256=$(curl -s -f "${sha_url}")

if [[ "$(sha256sum "${new_distro_tar}" | awk '{print $1}')" == "${sha256}" ]]; then
    echo "SHA256 checksum is valid. The package is intact."
else
    echo "SHA256 checksum mismatch! The file may be corrupt."
    exit 1
fi

echo "Unpacking..."
tar -xf "${new_distro_tar}" -C "${new_distro_dir}"
if [[ $? -ne 0 ]]; then
    echo "Error when unpacking tar"
fi

echo "Removing the tar file..."
rm -f "${new_distro_tar}"
rm -f "${new_distro_tar_enc}"

exec_start_path_template="___EXEC_START_PATH___"
exec_stop_path_template="___EXEC_STOP_PATH___"
script_version_template="___SCRIPT_VERSION___"
manifest="${new_distro_dir}/rpi/update.manifest.json"

# Get service file exec paths
wormholed_exec_start_path=$(jq -r '.files["wormholed-start"].path' "$manifest")
wormholed_exec_stop_path=$(jq -r '.files["wormholed-stop"].path' "$manifest")
wormholeinstalld_exec_path=$(jq -r ".files.wormholeinstalld.path" "$manifest")
wormholed_exec_start=$(eval echo "$wormholed_exec_start_path")
wormholed_exec_stop=$(eval echo "$wormholed_exec_stop_path")
wormholeinstalld_exec=$(eval echo "$wormholeinstalld_exec_path")

echo "Extracting files..."
for file_id in $(jq -r '.files | keys | .[]' "$manifest"); do
    source=$(jq -r ".files.\"$file_id\".source" "$manifest")
    path_literal=$(jq -r ".files.\"$file_id\".path" "$manifest")
    path=$(eval echo "$path_literal")
    echo "- ${source} to ${path}..."
    # Replace template with service file paths
    if [[ $file_id == "wormholed-service" ]]; then
        sed -i "s|${exec_start_path_template}|${wormholed_exec_start}|g" "${new_distro_dir}${source}"
        sed -i "s|${exec_stop_path_template}|${wormholed_exec_stop}|g" "${new_distro_dir}${source}"
    fi
    if [[ $file_id == "wormholeinstalld-service" ]]; then
        sed -i "s|${exec_start_path_template}|${wormholeinstalld_exec}|g" "${new_distro_dir}${source}"
    fi
    if [[ $file_id == "wormhole" ]]; then
        sed -i "s|${script_version_template}|${script_version}|g" "${new_distro_dir}${source}"
    fi
    
    # Copy temp file to install destination
    cp ${new_distro_dir}${source} "${path}"
done

rm -rf "${new_distro_dir}"

echo -e "Update complete"
