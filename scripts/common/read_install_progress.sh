#!/bin/bash

if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed."
    exit 1
fi
# Check arguments
if [ "$#" -ne 4 ]; then
    echo "Error: Incorrect number of arguments."
    echo "Usage: $0 \"<API_URL>\" \"<BEARER_TOKEN>\" \"<LINE_NUMBER>\" \"<OUTPUT_PREFIX>\""
    exit 1
fi
API_URL="$1"
BEARER_TOKEN="$2"
LINE_NUMBER="$3"
PREFIX="$4"

TIMESTAMP=$(date +%s%3N)
# Retry settings
retries=10
retry_timeout=1.0
current_timeout=$retry_timeout
for ((try_number=1; try_number<=retries; try_number++)); do
    # Create a payload
    PAYLOAD=$(jq --null-input \
                --argjson timestamp "$TIMESTAMP" \
                --argjson line "$LINE_NUMBER" \
                '{timestamp: $timestamp, line: $line}')
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
        # On success, clear the retry line from stderr and proceed
        # printf >&2 "\033[K"
        # Process response data on success
        SUCCESS=$(echo "$RESPONSE_BODY" | jq -r '.success')
        STATUS=$(echo "$RESPONSE_BODY" | jq -r '.status')
        LINE=$(echo "$RESPONSE_BODY" | jq -r '.line')
        TX_MS=$(echo "$RESPONSE_BODY" | jq -r '.ts')
        TIME_NOW=$(date +%s%3N)
        TOTAL_TIME=$(echo "$TIME_NOW - $TIMESTAMP" | bc -l)
        RX_MS=$(echo "$TOTAL_TIME - $TX_MS" | bc -l)
        # Format output
        TOTAL_TIME_F=$(echo "$TOTAL_TIME" | awk '{printf "%.3f", $1 / 1000}')
        TX_TIME_F=$(echo "$TX_MS" | awk '{printf "%.3f", $1 / 1000}')
        RX_TIME_F=$(echo "$RX_MS" | awk '{printf "%.3f", $1 / 1000}')
        if [ ! "$SUCCESS" == "true" ]; then
            printf "\033[K[%s/%sTX/%sRX] Error: %s\n" "$TOTAL_TIME_F" "$TX_TIME_F" "$RX_TIME_F" "$STATUS"
            exit 1
        else
            printf "%s%s\n" "${PREFIX}" "${LINE//%/%%}"
            printf "\033[K[%s/%sTX/%sRX] %s\n" "$TOTAL_TIME_F" "$TX_TIME_F" "$RX_TIME_F" "$STATUS"
            exit 0
        fi
    fi
    # If not the last try, print retry message to stderr and wait
    if [ "$try_number" -lt "$retries" ] && [ $HTTP_STATUS != 201 ]; then
        # printf >&2 "\033[KRetrying ${try_number}/${retries}...\r"
        sleep "$current_timeout"
        current_timeout="$(echo "$current_timeout + $retry_timeout" | bc)"
    fi
done
# If the loop finishes, all retries have failed. Report the error from the last attempt.
if [ "$curl_exit_code" -ne 0 ]; then
    echo "Error: The curl command failed with exit code $curl_exit_code"
else
    echo "Error: The HTTP request failed with status ${HTTP_STATUS} : ${RESPONSE_BODY}"
fi
exit 1
