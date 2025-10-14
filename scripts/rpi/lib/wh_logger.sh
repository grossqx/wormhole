#!/bin/bash

function wh_send_payload() {
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is not installed."
        return 1
    fi
    if [ "$#" -ne 2 ]; then
        echo "Error: Incorrect number of arguments."
        return 1
    fi
    local payload="$1"
    local api_url="$2"
    local timestamp=$(date +%s%3N)
    # Retry settings
    retries=10
    retry_timeout=1
    current_timeout=0
    for ((try_number=1; try_number<=retries; try_number++)); do
        if [ $try_number -gt 1 ]; then
            message="${message} (retry ${try_number})"
        fi
        temp_file=$(mktemp)
        CURL_OUTPUT=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $WH_HARDWARE_API_KEY" \
            -d "$payload" \
            -o "$temp_file" \
            -w "HTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
            -m 5 \
            "$api_url"
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
            TOTAL_TIME=$(echo "$TIME_NOW - $timestamp" | bc -l)
            RX_MS=$(echo "$TOTAL_TIME - $TX_MS" | bc -l)
            # Format output
            TOTAL_TIME_F=$(echo "$TOTAL_TIME" | awk '{printf "%.3f", $1 / 1000}')
            TX_TIME_F=$(echo "$TX_MS" | awk '{printf "%.3f", $1 / 1000}')
            RX_TIME_F=$(echo "$RX_MS" | awk '{printf "%.3f", $1 / 1000}')
            if [ ! "$SUCCESS" == "true" ]; then
                printf "[%s/%sTX/%sRX] Error: %s\n" "$TOTAL_TIME_F" "$TX_TIME_F" "$RX_TIME_F" "$STATUS"
                return 1
            else
                return 0
            fi
        fi
        # If not the last try, print retry message and wait
        if [ "$HTTP_STATUS" -ne 201 ] && [ "$HTTP_STATUS" -ne 401 ] && [ "$HTTP_STATUS" -ne 404 ]; then
            echo "status ${HTTP_STATUS}, retrying ${try_number}/${retries}..."
            current_timeout=$((current_timeout + retry_timeout))
            sleep "$current_timeout"
        else
            break
        fi
    done
    # If the loop finishes, all retries have failed. Report the error from the last attempt.
    if [ "$curl_exit_code" -ne 0 ]; then
        echo "Error: The curl command failed with exit code $curl_exit_code"
    else
        echo "Error: The HTTP request failed with status ${HTTP_STATUS}"
    fi
    return 1
}


function wh_log_local() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$WH_LOG_FILE"
}


function wh_log_remote() {
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is not installed."
        return 1
    fi
    # Check arguments
    if [ "$#" -ne 1 ]; then
        echo "Error: Incorrect number of arguments."
        return 1
    fi
    local message="$1"
    local api_url="${WH_SERVER_API_URL}/wh/log"
    local topic="$(whoami)"
    local timestamp=$(date +%s%3N)
    PAYLOAD=$(jq --null-input \
                --argjson timestamp "$timestamp" \
                --arg message "$message" \
                --arg topic "$topic" \
                '{timestamp: $timestamp, message: $message, topic: $topic}')
    wh_send_payload "$PAYLOAD" "$api_url"
}


function wh_log() {
    local message="$1"
    wh_log_local "$message"
    wh_log_remote "$message"
}