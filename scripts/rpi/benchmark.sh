#!/bin/bash

echo "Running benchmark"
cd $WH_HOME
echo "[1] Final system info"
rpi-sysinfo
echo "[2] Running disk benchmark"
#sudo ${WH_PATH}/third_party/disk-benchmark/disk-benchmark.sh
echo "[3] Finished"