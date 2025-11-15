#!/bin/bash

if [ -z "$WH_HARDWARE_API_KEY" ] || [ -z "$WH_SERVER_API_URL" ] || [ -z "$WH_CRYPTO_KEY" ] || [ -z "$WH_CRYPTO_CIPHER" ] || [ -z "$WH_CRYPTO_DERIVATION" ]; then
    echo "Error: One of the environment variables (WH_HARDWARE_API_KEY, WH_SERVER_API_URL, WH_CRYPTO_KEY, WH_CRYPTO_CIPHER, WH_CRYPTO_DERIVATION) are missing." >&2
    exit 1
fi
if [ -z "$docker_dir" ]; then
    echo "Error: docker_dir var empty"
    exit 1
fi

endpoint_update="/wh/rpi.docker"
api_domain=${WH_SERVER_API_URL}
distro_url="${WH_SERVER_API_URL}${endpoint_update}"
sha_url="${distro_url}.sha256"

echo "Updating wormhole's docker configuration from ${api_domain}"

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

echo "Contents of temporary directory:"
ls "${new_distro_dir}"

rm -rf "${docker_dir}"/*

echo "Copying new contents to ${docker_dir}..."
cp -r "${new_distro_dir}/." "${docker_dir}"
if [[ $? -ne 0 ]]; then
    echo "Error when copying files to ${docker_dir}"
    exit 1
fi

echo -e "Success. wormhole's docker configuration updated."