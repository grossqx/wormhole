#!/bin/bash

# Reports install progress to the server along with local hostname, user and a timestamp.
# Outputs latency information and server's response.
# This script is used by both the installer client and the Raspberry Pi itself.
# Uses install id as a token instead of user's personal token.

if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed."
    exit 1
fi
# Check arguments
if [ "$#" -ne 3 ]; then
    echo "Error: Incorrect number of arguments."
    echo "Usage: $0 \"<API_URL>\" \"<BEARER_TOKEN>\" \"<MESSAGE>\""
    exit 1
fi
API_URL="$1"
BEARER_TOKEN="$2"
MESSAGE="$3"

TIMESTAMP=$(date +%s%3N)
# Retry settings
retries=10
retry_timeout=1
current_timeout=0
for ((try_number=1; try_number<=retries; try_number++)); do
    if [ $try_number -gt 1 ]; then
        MESSAGE="${MESSAGE} (retry ${try_number})"
    fi
    # Create a payload
    HOSTNAME=$(hostname)
    USER=$(whoami)
    PAYLOAD=$(jq --null-input \
                --argjson timestamp "$TIMESTAMP" \
                --arg hostname "$HOSTNAME" \
                --arg user "$USER" \
                --arg message "$MESSAGE" \
                '{timestamp: $timestamp, hostname: $hostname, user: $user, message: $message}')
    # POST to server
    temp_file=$(mktemp)
    CURL_OUTPUT=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $BEARER_TOKEN" \
        -d "$PAYLOAD" \
        -o "$temp_file" \
        -w "HTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
        -m 5 \
        "$API_URL"
    )
    curl_exit_code=$?
    RESPONSE_BODY=$(cat "$temp_file")
    rm "$temp_file"

    # Check response
    HTTP_STATUS=$(echo "$CURL_OUTPUT" | sed -n 's/HTTP_CODE://p')
    if [ "$curl_exit_code" -eq 0 ] && [ "$HTTP_STATUS" -eq 200 ]; then
        # Process response data on success
        SUCCESS=$(echo "$RESPONSE_BODY" | jq -r '.success')
        STATUS=$(echo "$RESPONSE_BODY" | jq -r '.status')
        TX_MS=$(echo "$RESPONSE_BODY" | jq -r '.ts')
        TIME_NOW=$(date +%s%3N)
        TOTAL_TIME=$(echo "$TIME_NOW - $TIMESTAMP" | bc -l)
        RX_MS=$(echo "$TOTAL_TIME - $TX_MS" | bc -l)

        # Format output
        TOTAL_TIME_F=$(echo "$TOTAL_TIME" | awk '{printf "%.3f", $1 / 1000}')
        TX_TIME_F=$(echo "$TX_MS" | awk '{printf "%.3f", $1 / 1000}')
        RX_TIME_F=$(echo "$RX_MS" | awk '{printf "%.3f", $1 / 1000}')
        if [ ! "$SUCCESS" == "true" ]; then
            printf "[%s/%sTX/%sRX] Error: %s\n" "$TOTAL_TIME_F" "$TX_TIME_F" "$RX_TIME_F" "$STATUS"
            exit 1
        else
            exit 0
        fi
    fi
    # If not the last try, print retry message and wait
    if [ "$try_number" -lt "$retries" ] && [ $HTTP_STATUS != 201 ]; then
        echo "Retrying ${try_number}/${retries}..."
        sleep "$current_timeout"
        current_timeout=$((current_timeout + retry_timeout))
    fi
done

# If the loop finishes, all retries have failed. Report the error from the last attempt.
if [ "$curl_exit_code" -ne 0 ]; then
    echo "Error: The curl command failed with exit code $curl_exit_code"
else
    echo "Error: The HTTP request failed with status ${HTTP_STATUS}"
fi
exit 1