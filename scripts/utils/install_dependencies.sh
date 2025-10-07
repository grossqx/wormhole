#!/bin/bash

## Text colors:
source ${base_dir}/res/theme.env

RPI_DEPENDENCIES="rpi-imager bc unxz jq sed ip nmap"
PACKAGE_MANAGER_CMD=""

# Function to check for the existence of a command.
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to handle Arch-specific system update logic
function handle_arch_update() {
    echo -e "Detected Arch-like OS."
    get_user_input -y "This will perform a full system update with pacman -Syu to prevent conflicts. Do you agree?"
    if [[ $? -eq 0 ]]; then
        echo "Running system update..."
        sudo pacman -Syu --noconfirm
    else
        echo "Skipping system update. Proceeding with package installation."
    fi
}

RESOLVED_OS_ID=""
# --- PRIMARY METHOD: Detect OS using /etc/os-release ---
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    RESOLVED_OS_ID=$ID
    case "$ID" in
        debian|ubuntu|raspbian)
            PACKAGE_MANAGER_CMD="sudo apt-get install -y"
            echo "Detected apt."
            ;;
        fedora|rhel|centos|scientific)
            PACKAGE_MANAGER_CMD="sudo dnf install -y"
            echo "Detected dnf."
            ;;
        opensuse|suse)
            PACKAGE_MANAGER_CMD="sudo zypper install -y"
            echo "Detected zypper."
            ;;
        *)
            # Check ID_LIKE for Arch-based distributions
            if [[ "$ID_LIKE" == *"arch"* ]]; then
                PACKAGE_MANAGER_CMD="sudo pacman -S --noconfirm"
                echo "Detected zypper."
                handle_arch_update
            fi
            ;;
    esac
fi

# --- FALLBACK METHOD: Check command existence if the primary method failed ---
if [[ -z "$PACKAGE_MANAGER_CMD" ]]; then
    send_report "Unfamiliar os '${RESOLVED_OS_ID}'"
    echo "Unfamiliar os '${RESOLVED_OS_ID}'. Falling back to 'command_exists' method."

    if command_exists apt-get; then
        PACKAGE_MANAGER_CMD="sudo apt-get install -y"
        echo "Detected apt."
    elif command_exists dnf; then
        PACKAGE_MANAGER_CMD="sudo dnf install -y"
        echo "Detected dnf."
    elif command_exists yum; then
        PACKAGE_MANAGER_CMD="sudo yum install -y"
        echo "Detected yum."
    elif command_exists zypper; then
        PACKAGE_MANAGER_CMD="sudo zypper install -y"
        echo "Detected zypper."
    elif command_exists pacman; then
        PACKAGE_MANAGER_CMD="sudo pacman -S --noconfirm"
        echo "Detected pacman."
        handle_arch_update
    fi
fi

# --- Check if a package manager was found after all attempts ---
if [[ -z "$PACKAGE_MANAGER_CMD" ]]; then
    echo "Error: Could not detect a supported package manager."
    send_report "Could not detect a supported package manager"
    exit 1
fi

send_report "Detected install command - ${PACKAGE_MANAGER_CMD}"

# List dependencies with descriptions
echo -e "${T_BBLUE}This script requires the following dependencies:${T_NC}"
echo -e "${T_ITALIC}Note: Many of these are standard command-line tools and may already be installed on your system.${T_NC}"
for RPI_DEP in $RPI_DEPENDENCIES; do
    case "$RPI_DEP" in
        "rpi-imager")
            echo -e "  ${T_BBLUE}rpi-imager${T_NC}: ${T_ITALIC}Official tool for writing OS images to SD cards.${T_NC}"
            ;;
        "bc")
            echo -e "  ${T_BBLUE}bc${T_NC}: ${T_ITALIC}GNU bc calculator for performing arbitrary-precision arithmetic calculations.${T_NC}"
            ;;
        "unxz")
            echo -e "  ${T_BBLUE}unxz${T_NC}: ${T_ITALIC}Decompression utility for .xz compressed files, common for OS images.${T_NC}"
            ;;
        "jq")
            echo -e "  ${T_BBLUE}jq${T_NC}: ${T_ITALIC}Command-line JSON processor for parsing and manipulating data.${T_NC}"
            ;;
        "sed")
            echo -e "  ${T_BBLUE}sed${T_NC}: ${T_ITALIC}Stream editor for filtering and transforming text.${T_NC}"
            ;;
        "ip")
            echo -e "  ${T_BBLUE}ip${T_NC}: ${T_ITALIC}Tool for showing and managing network routes and devices.${T_NC}"
            ;;
        "nmap")
            echo -e "  ${T_BBLUE}nmap${T_NC}: ${T_ITALIC}Network scanner for discovering hosts and services on a network.${T_NC}"
            ;;
    esac
done

# Get confirmation for dependency installation
send_report "Waiting for consent"
get_user_input -y "Do you agree?"
if [[ $? -eq 0 ]]; then
    send_report "Agreed to install dependencies"
else
    echo "Installation aborted."
    send_report "Refused to install dependencies"
    exit 1
fi

# Get the total number of dependencies
DEP_TOTAL=$(echo $RPI_DEPENDENCIES | wc -w)
COUNTER=1

# Loop over dependencies and install them one by one
for RPI_DEP in $RPI_DEPENDENCIES; do
    echo -e "${T_BLUE}Installing dependency (${COUNTER}/${DEP_TOTAL}): ${RPI_DEP} ${T_NC}"
    send_report "Installing ${RPI_DEP}"
    ${PACKAGE_MANAGER_CMD} ${RPI_DEP}
    echo
    COUNTER=$((COUNTER + 1))
done

echo -e ${T_BBLUE}Installed versions:${T_NC}
for RPI_DEP in $RPI_DEPENDENCIES; do
    if command_exists "$RPI_DEP"; then
        printf "${T_GREEN}${RPI_DEP}:${T_NC} "
        case "$RPI_DEP" in
            ip)
                $RPI_DEP -V
                ;;
            nmap|sed|bc)
                $RPI_DEP --version | head -n 1
                ;;
            *)
                $RPI_DEP --version
                ;;
        esac
    else
        echo -e "${T_GREEN}${RPI_DEP}:${T_NC}"
        echo "Command not found. Installation may have failed."
    fi
done
echo
echo -e ${T_GREEN}All dependencies installed!${T_NC}
exit 0