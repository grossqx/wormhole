#!/bin/bash

url=$1
api_key=$2

TIMEOUT=20

## Text colors:
source ${base_dir}/res/theme.env

response=$(curl -s -w "\n%{http_code}" --max-time ${TIMEOUT} -X GET ${url} -H "Authorization: Bearer ${api_key}")
http_code=$(echo "$response" | tail -n1) # Extract the last line for the status code
data=$(echo "$response" | sed '$d') # Remove the last line to get the data
if [[ "$http_code" == "200" ]]; then
   echo $data
else
   echo "${T_RED}Error: ${http_code} - Response body: ${data}${T_NC}"
   exit 1
fi