#!/bin/bash

## Settings
TARGET_DEVICE=$1
DEVICE_TAG=$2
OS_SEARCH_STRING=$3
WRITE_TIMEOUT=$4
FIRSTRUN_SCRIPT=$5

VERBOSE=1

## Text colors:
source ${base_dir}/res/theme.env


# Function to check the SHA256 checksum of a file
# Arguments:
#   $1: The path to the file
#   $2: The expected SHA256 checksum string
function verify_sha256() {
    local file_path="$1"
    local expected_sha256="$2"
    echo
    echo -e "${T_BLUE}Checking file integrity...${T_NC}"    
    if [ ! -f "$file_path" ]; then
        echo -e "${T_BRED}Error: File not found at '$file_path'.${T_NC}"
        return 1
    fi
    calculated_sha256=$(sha256sum "$file_path" | awk '{print $1}')
    if [[ "$calculated_sha256" == "$expected_sha256" ]]; then
        echo -e "${T_GREEN}SHA256 checksum is valid. The file is intact.${T_NC}"
        return 0
    else
        echo -e "${T_BRED}SHA256 checksum mismatch! The file may be corrupt.${T_NC}"
        echo "Expected:   $expected_sha256"
        echo "Calculated: $calculated_sha256"
        return 1
    fi
}

image_dir=$HOME/.cache/wormhole

# Get repository URL from rpi-imager
rpi_imager_output=$(rpi-imager --version 2>&1)
RPI_REPO=$(echo $rpi_imager_output | grep -o 'https://.*')
RPI_IMAGER_VER=$(echo $rpi_imager_output | grep -oP 'version \K\S+')
echo "Current Raspberry repository is ${RPI_REPO}"
echo "Fetching data on OS images..."
data=$(curl -s "$RPI_REPO")
if [ -z "$data" ]; then
    echo -e "${T_BRED}Error: Could not fetch data from the repository.${T_NC}"
    exit 1
fi
latest_version=$(echo "$data" | jq -r '.imager.latest_version')
if [ "${latest_version}" != "${RPI_IMAGER_VER}" ]; then
    echo -e "${T_BYELLOW}Warning: Current version of rpi-imager is older than the latest one. ${T_RED}${RPI_IMAGER_VER}${T_NC} vs ${T_GREEN}${latest_version}${T_NC}"
fi

# Process data with a recursive jq filter
image_names=$(echo $data | jq -r --arg tag "$DEVICE_TAG" '
  .. | select(type == "object" and has("devices") and has("url") and (.devices | contains([$tag]))) | .name
')
image_urls=$(echo $data | jq -r --arg tag "$DEVICE_TAG" '
  .. | select(type == "object" and has("devices") and has("url") and (.devices | contains([$tag]))) | .url
')
if [ -z "$image_urls" ]; then
    echo -e "${T_BRED}Error: Could not process data from the repository.${T_NC}"
    exit 1
fi

## Parse strings into arrays
IFS=$'\n' read -r -d '' -a image_array <<< "$image_names"
IFS=$'\n' read -r -d '' -a url_array <<< "$image_urls"

# # Initialize a counter and a new empty array for the matches
matching_count=0
matching_images=()
matching_names=()

# Find and count images that are compatible by tag
COUNTER=1
if [[ ${VERBOSE} -gt 1 ]]; then
    echo -e "${T_BBLUE}Compatible images:${T_NC}"
fi
for name in "${image_array[@]}"; do
    if [[ "$name" =~ "$OS_SEARCH_STRING" ]]; then
        MATCH_COUNT=$((MATCH_COUNT + 1))
        matching_images+=($((COUNTER - 1)))
        matching_names+=("${name}")
    fi
    if [[ ${VERBOSE} -gt 1 ]]; then
        echo "  ${COUNTER}. $name"
    fi
    COUNTER=$((COUNTER + 1))
done
echo -e "${T_BBLUE}A total of ${#image_array[@]} compatible images were found.${T_NC}"

# Output based on the number of found images
COUNTER=1
if [ ${#matching_images[@]} -eq 1 ]; then
    echo -e "${T_BBLUE}Found a single image matching the criteria '${OS_SEARCH_STRING}' from your configuration:${T_NC}"
    CHOSEN_IMAGE_ID=1
    CHOSEN_IMAGE_NAME="${matching_names[0]}"
elif [ ${#matching_images[@]} -gt 1 ]; then
    echo -e "${T_BYELLOW}Multiple images found matching criteria '${OS_SEARCH_STRING}' from your configuration:${T_NC}"
    for name in "${matching_names[@]}"; do
        echo "  ${COUNTER}. $name"
        COUNTER=$((COUNTER + 1))
    done
    COUNTER=$((COUNTER-1))
    max_option=${COUNTER}
    while true; do
        read -p "Enter a number between 1 and $COUNTER to download the image: " choice
        # Check if the input is a valid number and within the range
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${COUNTER} )); then
            echo "You chose option $choice."
            CHOSEN_IMAGE_ID="$choice"
            id=$((CHOSEN_IMAGE_ID - 1))
            CHOSEN_IMAGE_NAME="${matching_names[$id]}"
            break  # Exit the loop since a valid choice has been made
        else
            echo -e "${T_BYELLOW}Invalid input. Please enter a number between 1 and $COUNTER.${T_NC}"
        fi
    done
else
    echo -e "${T_BRED}No images with '${OS_SEARCH_STRING}' in the name were found. Please adjust the search criteria!${T_NC}"
    exit 1
fi

# Select image object from data
image_data=$(echo "$data" | jq -r --arg tag "$DEVICE_TAG" --arg name "$CHOSEN_IMAGE_NAME" '
  .. | select(type == "object" and has("devices") and has("url") and has("name") and (.devices | contains([$tag])) and (.name == $name))
')

# Get details
i_name=$(echo "$image_data" | jq -r '.name')
i_description=$(echo "$image_data" | jq -r '.description')
i_extract_sha256=$(echo "$image_data" | jq -r '.extract_sha256')
i_release_date=$(echo "$image_data" | jq -r '.release_date')
i_url=$(echo "$image_data" | jq -r '.url')
echo -e "${T_BBLUE} - ${T_BOLD}${i_name}${T_NC}"
echo -e "   ${T_ITALIC}${i_description}${T_NC}"
echo "   released ${i_release_date}"
echo "   sha256 ${i_extract_sha256}"
echo
send_report "Client picked image: \n${i_name}\nDescription:${i_description}\nRelease date: ${i_release_date}\nsha256: ${i_extract_sha256}"

# Downloading the image
image_path=${image_dir}/$(basename "$i_url")
uncompressed_path=${image_path%.xz}
IMAGE_READY=true
# Check if the uncompressed file already exists
if [[ -e "$uncompressed_path" ]]; then
    if verify_sha256 "$uncompressed_path" "$i_extract_sha256"; then
        get_user_input -n "${YELLOW}The file already exists. Do you want to re-download it?${NC}"
        if [[ $? -eq 0 ]]; then
            IMAGE_READY=false
        fi
    else
        IMAGE_READY=false
    fi
else
    IMAGE_READY=false
fi

# Final confirmation from the user
send_report "Waiting for final confirmation before write"
echo -e "${T_YELLOW}${T_BOLD}All partitions on ${TARGET_DEVICE} will be wiped and the image will be written on top.${T_NC}"
get_user_input "${T_RED}${T_BOLD}Are you ABSOLUTELY sure you want to proceed?${T_NC}"
if [[ $? -eq 0 ]]; then
    send_report "Confirmation received"
    echo "Will write the image ${i_name} to ${TARGET_DEVICE}"
    echo "Waiting for ${WRITE_TIMEOUT} in case you change your mind... CTRL + C to cancel."
    sleep ${WRITE_TIMEOUT}
    tput clear
    echo -e "${T_GREEN}Starting..."
    echo -e "${T_GREEN}This will take a while. You can go enjoy a cup of coffee!${T_NC} ☕🚬"
else
    echo "Operation cancelled. Image has not been written anywhere"
    send_report "Write canceled by client"
    exit 1
fi

# If needed, download and uncompress the file
if [[ "$IMAGE_READY" == "false" ]]; then
    echo
    send_report "Starting image download"
    echo -e "${T_BLUE}Starting download...${T_NC}"
    rm -f $image_path
    wget -P "${image_dir}" "${i_url}"
    result=$?
    if [[ ! $result -eq 0 ]]; then
        echo -e "${T_RED}Error: Failed to download the image."
        send_report "Failed to download the image"
        exit 1
    fi
    if [[ "$image_path" == *.xz ]]; then
        echo
        send_report "Uncompressing the image"
        echo -e "${T_BLUE}Uncompressing the tarball...${T_NC}"
        unxz -d -f -v "$image_path"
        result=$?
        if [[ ! $result -eq 0 ]]; then
            echo -e "${T_RED}Error: Failed to uncompress the image."
            send_report "Failed to uncompress the image"
            exit 1
        fi
    fi
    if verify_sha256 "$uncompressed_path" "$i_extract_sha256"; then
        echo
        echo -e "${T_BLUE}Image ready to be written to media${T_NC}"
        echo "${uncompressed_path}"
        send_report "image file ${uncompressed_path}"
        echo
    else
        send_report "verify_sha256 failed"
        exit 1
    fi
fi

echo -e "${T_BLUE}Wiping previous content and writing to $TARGET_DEVICE...${T_NC}"
send_report "Starting the image write process"
sudo rpi-imager --cli --first-run-script "${FIRSTRUN_SCRIPT}" --debug "${uncompressed_path}" "${TARGET_DEVICE}"
result=$?
if [[ ! $result -eq 0 ]]; then
    echo -e "${T_RED}Error: Failed to write the image.${T_NC}"
    send_report "rpi-imager has failed"
    exit 1
else
    echo -e "${T_GREEN}Success!${T_NC}"
fi

send_report "rpi-imager done"

echo -e "${T_BLUE}Clean-up${T_NC}"
echo -e "${uncompressed_path} takes up $(du -sh ${uncompressed_path} | awk {'print $1'})"
get_user_input -n "${T_BLUE}Do you want to clean up the iso file?${T_NC}"
if [[ $? -eq 0 ]]; then
    echo "removing ${uncompressed_path}"
    rm "${uncompressed_path}"
fi