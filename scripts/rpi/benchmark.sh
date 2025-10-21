#!/bin/bash

ip_scan_ranges="192.168.0.0/24"
top_scan_ports=1000

echo "Running benchmark"
cd $WH_HOME
echo "[1] Final system info"
rpi-sysinfo
echo "[2] Running disk benchmark"

sudo ${WH_PATH}/third_party/disk-benchmark/disk-benchmark.sh

echo "[3] Network state"
nmcli general
echo "[4] Network devices"
nmcli device
echo "[5] WiFi networks"
nmcli device wifi list --rescan yes
echo "[6] Other hosts"
nmap --top-ports ${top_scan_ports} ${ip_scan_ranges} 
echo "[7] Finished"