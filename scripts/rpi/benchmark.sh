#!/bin/bash

ip_scan_ranges="192.168.0.0/24"
top_scan_ports=100

echo "[0/7] Running benchmark"

echo "[1/7] Final system info"
rpi-sysinfo

echo "[2/7] Running disk benchmark"
sudo ${WH_PATH}/third_party/disk-benchmark/disk-benchmark.sh

echo "[3/7] Network state"
nmcli general

echo "[4/7] Network devices"
nmcli device

echo "[5/7] WiFi networks"
nmcli device wifi list --rescan yes

echo "[6/7] Other hosts"
nmap --top-ports ${top_scan_ports} ${ip_scan_ranges} 

echo "[7/7] Finished"