#!/bin/bash


#####################################################################################
# This script provides functions to embed binary or text files into a shell script
# and later extract them using a unique identifier.
#
# Functions:
#   - embed_file: Packs a file into a script using a unique ID.
#   - extract_embedded_file_simple: Extracts a file from the script by ID (basic version).
#   - get_file_unpack_path: Retrieves the default extraction path from an embedded file.
#   - extract_file: The main function to extract a file by ID and optionally to a specified path.
#   - extract_systemd_service: Extracts, modifies, and installs an embedded systemd service file.
#
# Usage:
#   1. Make the script executable:
#      chmod +x your_script.sh
#
#   2. To embed a file into the script:
#      source your_script.sh
#      embed_file /path/to/source.zip archive.sh my_data /tmp/data
# 
#   3. To extract an embedded file from the script:
#      source your_script.sh
#      extract_file my_data /tmp/data/extracted_data.config
#
#####################################################################################

## Example of marker without a filepath
#___START_FILE_CONTENT___installer_temp_service___
## Content
#EOF

## Example of marker with a filepath
#___START_FILE_CONTENT___test_file___/home/gqx/test_file.txt___
## Content
#EOF

# Function to embed a file into a self-extracting shell script
function embed_file() {
    local SOURCE_FILE="$1"
    local PACK_FILE="$2"
    local FILE_ID="$3"
    local UNPACK_PATH="$4"

    # This single IF block handles all cases where help should be displayed. It checks for the help flag OR for missing required arguments.
    if [[ "$SOURCE_FILE" == "-h" || "$SOURCE_FILE" == "--help" || -z "$SOURCE_FILE" || -z "$PACK_FILE" || -z "$FILE_ID" ]]; then
        # Help
        echo "Usage: embed_file <source_file> <pack_file> <file_id> [unpack_path]"
        echo
        echo "This function packs a source file into a self-extracting shell script, associating it with a specific file ID."
        echo
        echo "Arguments:"
        echo "  <source_file>  The file that will be packed."
        echo "  <pack_file>    The destination self-extracting .sh script."
        echo "  <file_id>      The required ID to associate with the packed file. This ID is necessary to uniquely identify and extract the file later."
        echo "  [unpack_path]  (Optional) The path to encode for later extraction. The file will be extracted to this path by default."
        echo
        echo "Examples:"
        echo "  # Pack 'config.conf' into 'archive.sh'"
        echo "  embed_file config.conf archive.sh conf_123"
        echo
        echo "  # Pack 'run.sh' into 'my_data.sh' and encode '/etc/app' as the default extraction path"
        echo "  embed_file run.sh my_data.sh script_456 /etc/app"
        # This nested IF determines the return code based on the specific condition.
        if [[ "$SOURCE_FILE" == "-h" || "$SOURCE_FILE" == "--help" ]]; then
            # If the help flag was explicitly used, return success.
            return 0
        else
            # Otherwise, the help message was triggered by a missing argument.
            echo "Error: Missing one or more required arguments." >&2
            echo "source_file - ${SOURCE_FILE}" >&2
            echo "pack_file - ${PACK_FILE}" >&2
            echo "file_id - ${FILE_ID}" >&2
            return 1
        fi
    fi
    # Check if the source file exists and is a regular file
    if [[ ! -f "$SOURCE_FILE" ]]; then
        echo "Error: Source file '$SOURCE_FILE' does not exist or is not a regular file." >&2
        return 1
    fi
    # Check if the pack file has the required .sh extension
    if [[ ! "$PACK_FILE" == *.sh ]]; then
        echo "Error: The destination pack file must be a self-extracting .sh file." >&2
        return 1
    fi
    # Check if the pack file exists before trying to grep it
    if [[ -f "$PACK_FILE" ]]; then
        # Check if file ID is already in the archive file
        if grep -q "^___START_FILE_CONTENT___${FILE_ID}___" "$PACK_FILE"; then
            echo "Error: The ID '${FILE_ID}' is already embedded in '${PACK_FILE}'. Cannot embed duplicate files." >&2
            return 1
        fi
    fi
    local TEMP_FILE=$(mktemp)
    if [[ -z "$UNPACK_PATH" ]]; then
        echo > "$TEMP_FILE"
        echo "#####################################################################################" >> "$TEMP_FILE"
        echo "### ${FILE_ID}" >> "$TEMP_FILE"
        echo "#####################################################################################" >> "$TEMP_FILE"
        echo "cat << EOF | /dev/null" >> "$TEMP_FILE"
        echo "___START_FILE_CONTENT___${FILE_ID}___" >> "$TEMP_FILE"
        cat "$SOURCE_FILE" >> "$TEMP_FILE"
        echo >> "$TEMP_FILE"
        echo "EOF" >> "$TEMP_FILE"
        echo "#####################################################################################" >> "$TEMP_FILE"
    else
        echo > "$TEMP_FILE"
        echo "#####################################################################################" >> "$TEMP_FILE"
        echo "### ${FILE_ID}     extract path: ${UNPACK_PATH}" >> "$TEMP_FILE"
        echo "#####################################################################################" >> "$TEMP_FILE"
        echo "cat << EOF | /dev/null" >> "$TEMP_FILE"
        echo "___START_FILE_CONTENT___${FILE_ID}___${UNPACK_PATH}___" >> "$TEMP_FILE"
        cat "$SOURCE_FILE" >> "$TEMP_FILE"
        echo >> "$TEMP_FILE"
        echo "EOF" >> "$TEMP_FILE"
        echo "#####################################################################################" >> "$TEMP_FILE"
    fi
    local NEW_PACK_FILE=$(mktemp)
    if [[ -f "$PACK_FILE" ]]; then
        (
            head -n 1 "$PACK_FILE"
            cat "$TEMP_FILE"
            tail -n +2 "$PACK_FILE"
        ) > "$NEW_PACK_FILE"
    else
        echo "#!/bin/bash" > "$NEW_PACK_FILE"
        cat "$TEMP_FILE" >> "$NEW_PACK_FILE"
    fi
    mv "$NEW_PACK_FILE" "$PACK_FILE"
    chmod +x "$PACK_FILE"
    rm "$TEMP_FILE"
    if [[ -z "$UNPACK_PATH" ]]; then
        echo -e "'$(basename "${PACK_FILE}")' packed with '$(basename "${SOURCE_FILE}")' (id ${FILE_ID})"
    else
        echo -e "'$(basename "${PACK_FILE}")' packed with '$(basename "${SOURCE_FILE}")' (id ${FILE_ID}:${UNPACK_PATH})"
    fi
}


function extract_embedded_file_simple() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: extract_file_simple <name>"
        return 1
    fi
    local start_line=$(grep -m 1 -n "^___START_FILE_CONTENT___${name}___" "$0" | cut -d: -f1)
    if [[ -z "$start_line" ]]; then
        echo "Error: Start line for ${name} not found in $0"
        return 1
    fi
    local file_path_literal=$(sed -n "${start_line}s/^___START_FILE_CONTENT___${name}___\(.*\)___$/\1/p" "$0")
    if [[ -z "$file_path_literal" ]]; then
        echo "Error: Extract file for ${name} path not found in $0"
        return 1
    fi
    local file_path=$(eval echo "$file_path_literal")
    local end_line=$(awk "NR > $start_line && /^EOF$/ {print NR; exit}" "$0")
    if [[ -z "$end_line" ]]; then
        echo "Error: EOF for ${name} not found in $0"
        return 1
    fi
    mkdir -p "$(dirname "$file_path")"
    sed -n "$(($start_line + 1)),$(($end_line - 1))p" "$0" > "$file_path"
    chmod +x "${file_path}"
    echo "Extracted ${name} to ${file_path}"
}

# This function retrieves the file path from the start marker for a given file name.
# It takes the file name as an argument and prints the corresponding file path to stdout.
# Returns 0 on success and 1 on failure.
function get_file_unpack_path() {
    local source_script="$1"
    local name="$2"
    if [[ "$source_script" == "-h" || "$source_script" == "--help" ]]; then
        echo "Usage: get_file_unpack_path <source_script> <name>"
        return 0
    fi
    if [[ -z "$source_script" || -z "$name" ]]; then
        echo "Error: Missing one or more required arguments." >&2
        echo "Usage: get_file_unpack_path <source_script> <name>" >&2
        return 1
    fi
    if [[ ! -f "$source_script" ]]; then
        echo "Error: Source script '$source_script' not found." >&2
        return 1
    fi
    local file_path=$(sed -n "s/^___START_FILE_CONTENT___${name}___\(.*\)___$/\1/p" "$source_script")
    if [[ -z "$file_path" ]]; then
        echo "Error: No file path found for '${name}' in '${source_script}'." >&2
        return 1
    fi
    echo "$file_path"
}

# This function extracts an embedded file from the script itself.
# It identifies the file by a start marker that contains its name and destination path,
# and ends with an EOF marker. The content is then written to the determined path.
function extract_file() {
    local name="$1"
    local output_path="$2"
    local source_script="${3:-$0}" # Default to the current script if not provided
    if [[ "$name" == "-h" || "$name" == "--help" ]]; then
        echo "Usage: extract_file <name> [output_path] [source_script]"
        return 0
    fi
    if [[ -z "$name" ]]; then
        echo "Error: Missing required argument <name>." >&2
        echo "Usage: extract_file <name> [output_path] [source_script]" >&2
        return 1
    fi
    if [[ ! -f "$source_script" ]]; then
        echo "Error: Source script '$source_script' not found." >&2
        return 1
    fi
    local file_path_literal
    if [[ -n "$output_path" ]]; then
        file_path_literal="$output_path"
    else
        file_path_literal=$(get_file_unpack_path "$source_script" "$name")
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi
    local file_path=$(eval echo "$file_path_literal")
    local start_line=$(grep -m 1 -n "^___START_FILE_CONTENT___${name}___" "$source_script" | cut -d: -f1)
    if [[ -z "$start_line" ]]; then
        echo "Error: Start marker for '${name}' not found in '${source_script}'." >&2
        return 1
    fi
    local end_line=$(awk "NR > $start_line && /^EOF$/ {print NR; exit}" "$source_script")
    if [[ -z "$end_line" ]]; then
        echo "Error: EOF marker not found for '${name}' in '${source_script}'." >&2
        return 1
    fi
    local file_dir=$(dirname "$file_path")
    if [[ ! -d "$file_dir" ]]; then
        echo "Creating directory: ${file_dir}"
        mkdir -p "$file_dir"
    fi
    sed -n "$(($start_line + 1)),$(($end_line - 1))p" "$source_script" > "$file_path"
    chmod +x ${file_path}
    echo "Extracted an executable from '${source_script}' to '${file_path}'"
}

# This function extracts an embedded systemd service file (specified by name) from the installer,
# replaces a template string with the specified script path, and installs it.
# Arguments:
#   $1: The name of the embedded service file to extract.
#   $2: The path to the installer script that the service file will execute.
#   $3: The destination path for the new systemd service file (e.g., /etc/systemd/system/myservice.service).
function extract_systemd_service() {
    local embedded_service_name="$1"
    local exec_start_script_path="$2"
    local systemd_service_path="$3"
    local source_script="${4:-$0}" # Default to the current script if not provided
    local exec_start_path_template="___EXEC_START_PATH___"
    # Check for help flag
    if [[ "$embedded_service_name" == "-h" || "$embedded_service_name" == "--help" ]]; then
        echo "Usage: extract_systemd_service <embedded_service_name> <exec_start_script_path> <systemd_service_path> [source_script]"
        echo ""
        echo "This function extracts a systemd service file, replaces a template string, and copies it."
        echo "Arguments:"
        echo "  <embedded_service_name>  The name of the embedded service file to extract."
        echo "  <exec_start_script_path> The path to the installer script to be inserted into the service file."
        echo "  <systemd_service_path>   The destination path for the extracted and modified systemd service file."
        echo "  [source_script]          (Optional) The path to the script containing the embedded service file. Defaults to the current script."
        return 0
    fi
    # Check for missing arguments
    if [[ -z "$embedded_service_name" || -z "$exec_start_script_path" || -z "$systemd_service_path" ]]; then
        echo "Error: Missing one or more required arguments." >&2
        echo "Usage: extract_systemd_service <embedded_service_name> <exec_start_script_path> <systemd_service_path> [source_script]" >&2
        return 1
    fi
    if [[ ! -f "$source_script" ]]; then
        echo "Error: Source script '$source_script' not found." >&2
        return 1
    fi
    local temp_file=$(mktemp)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create a temporary file." >&2
        return 1
    fi
    extract_file "$embedded_service_name" "$temp_file" "$source_script"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to extract embedded file from '$source_script'." >&2
        rm -f "$temp_file"
        return 1
    fi
    if ! grep -q "$exec_start_path_template" "$temp_file"; then
        echo "Error: The template string '${exec_start_path_template}' was not found in the service file." >&2
        rm -f "$temp_file"
        return 1
    fi
    local exec_start_script=$(eval echo "$exec_start_script_path")
    sed -i "s|${exec_start_path_template}|${exec_start_script}|g" "$temp_file"
    sudo cp "$temp_file" "$systemd_service_path"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to copy file with sudo." >&2
        rm -f "$temp_file"
        return 1
    fi
    rm -f "$temp_file"
    echo "systemd service file extracted from '${source_script}' to '${systemd_service_path}'"
}