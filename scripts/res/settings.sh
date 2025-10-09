#!/bin/bash

script_version="0.1.14"

# Encryption
key_derivation="-pbkdf2"
crypto_cipher="-aes-256-cbc"
crypto_key="seed"

# Array of public DNS servers to test for connectivity.
declare -a test_hosts=("isc.org" "google.com" "cloudflare.com" "1.1.1.1" "8.8.8.8")
ping_timeout=10