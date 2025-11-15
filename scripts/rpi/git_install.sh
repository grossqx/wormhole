#!/bin/bash

# Default values
SKIP_GIT_INSTALL=false
INSTALL_LFS=false
REGISTER_IDENTITY=false
GENERATE_SSH_GITHUB=false
GENERATE_SSH_OTHER=false
CHECK_SSH=false
OTHER_SSH_HOST=""
INSTALL_CMD="apt-get install -y"
INSTALL_CMD_PROVIDED=false
TARGET_USER=""

# Function to display help information
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script installs and configures Git, with optional features."
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message and exit."
    echo "  -s, --skip-git-install  Skip Git installation. The script will only perform "
    echo "                          the requested actions if Git is already installed."
    echo "  -e, --external-install-command \"COMMAND\"  Provide a custom installation command. "
    echo "                          Example: --external-install-command \"dnf install -y\""
    echo "  -l, --lfs               Install Git LFS in addition to Git."
    echo "  -i                      Register Git identity using GITHUB_EMAIL and GITHUB_NAME."
    echo "                          Requires GITHUB_EMAIL and GITHUB_NAME to be set."
    echo "  -g, --github            Generate a specific SSH key for GitHub."
    echo "                          Assumes Git identity will also be set."
    echo "  -o, --git-host USER@URL  Generate a specific SSH key for another Git server."
    echo "                          Assumes Git identity will also be set."
    echo "  -c, --check [USER@URL]  Perform an SSH connectivity check and exit. Optional"
    echo "                          argument to specify the host. Default is git@github.com."
    echo "  -u, --user USERNAME     Specify the user for whom to perform the actions."
    echo "                          Optional. Defaults to the current user."
    echo ""
    echo "Note: The -c option will perform only the check and exit, ignoring other options."
    exit 0
}

# Parse command-line options
for arg in "$@"; do
    case $arg in
        -h|--help)
            show_help
            ;;
        -s|--skip-git-install)
            SKIP_GIT_INSTALL=true
            ;;
        -e|--external-install-command)
            INSTALL_CMD_PROVIDED=true
            shift # consume '-e' or '--external-install-command'
            INSTALL_CMD="$1"
            shift # consume the argument
            ;;
        -l|--lfs)
            INSTALL_LFS=true
            ;;
        -i)
            REGISTER_IDENTITY=true
            ;;
        -g|--github)
            GENERATE_SSH_GITHUB=true
            ;;
        -o|--git-host)
            GENERATE_SSH_OTHER=true
            shift # consume '-o' or '--git-host'
            OTHER_SSH_HOST="$1"
            shift # consume the argument
            ;;
        -c|--check)
            CHECK_SSH=true
            shift # consume '-c' or '--check'
            if [ -n "$1" ] && [[ ! "$1" =~ ^- ]]; then
                OTHER_SSH_HOST="$1"
                shift # consume the optional argument
            fi
            ;;
        -u|--user)
            shift # consume '-u' or '--user'
            TARGET_USER="$1"
            shift # consume the argument
            ;;
        *)
            # Stop parsing options if a non-option argument is found
            echo "Error: Invalid argument: $arg" >&2
            exit 1
            ;;
    esac
done

# Handle SSH check as a standalone action and exit
if [ "$CHECK_SSH" = true ]; then
    if [ -z "$OTHER_SSH_HOST" ]; then
        CHECK_HOST="git@github.com"
    else
        CHECK_HOST="$OTHER_SSH_HOST"
    fi
    echo "Checking SSH connectivity to ${CHECK_HOST}..."
    ssh -T "$CHECK_HOST"
    if [ $? -eq 0 ]; then
        echo "SSH connection to ${CHECK_HOST} successful!"
        exit 0
    else
        echo "Error: SSH connection to ${CHECK_HOST} failed. Please check your key and configuration."
        exit 1
    fi
fi

# Check for a single required argument
if [ "$GENERATE_SSH_OTHER" = true ] && [ -z "$OTHER_SSH_HOST" ]; then
    echo "Error: -o or --git-host option requires an argument (e.g., user@url). Exiting."
    exit 1
fi

# Check for required environment variables for identity and key generation
if [ "$REGISTER_IDENTITY" = true ] || [ "$GENERATE_SSH_GITHUB" = true ] || [ "$GENERATE_SSH_OTHER" = true ]; then
    if [ -z "$GITHUB_EMAIL" ]; then
        echo "Error: GITHUB_EMAIL must be set to register identity or generate SSH keys. Exiting."
        exit 1
    fi
    if [ "$REGISTER_IDENTITY" = true ] && [ -z "$GITHUB_NAME" ]; then
        echo "Error: GITHUB_NAME must be set to register Git identity. Exiting."
        exit 1
    fi
fi

# Determine the target user and their home directory (last check)
if [ "$REGISTER_IDENTITY" = true ] || [ "$GENERATE_SSH_GITHUB" = true ] || [ "$GENERATE_SSH_OTHER" = true ]; then
    if [ -z "$TARGET_USER" ]; then
        TARGET_USER="$USER"
        USER_HOME="$HOME"
        echo "No user specified. Defaulting to current user: $TARGET_USER"
    else
        USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
        if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
            echo "Error: User '$TARGET_USER' not found or has no home directory. Exiting."
            exit 1
        fi
        echo "Target user specified: $TARGET_USER. Home directory: $USER_HOME"
    fi
fi

echo "[0/3] Initial checks completed."

echo "[1/3] Beginning installation..."

if [ "$SKIP_GIT_INSTALL" = true ]; then
    echo "Skipping Git installation as requested."
    if command -v git &> /dev/null; then
        echo "Git is already installed. Version: $(git --version)."
    else
        echo "Error: Git not found. To install it, run the script without the -s option."
        exit 1
    fi
else
    message="Installing git"
    packages_to_install="git"
    if [ "$INSTALL_LFS" = true ]; then
        message="${message} and git-lfs..."
        packages_to_install="${packages_to_install} git-lfs"
    else
        message="${message} ..."
    fi
    echo $message
    $INSTALL_CMD $packages_to_install
    if [ $? -eq 0 ]; then
        echo "Git installed successfully."
    else
        echo "Error: Failed to install Git. Exiting."
        exit 1
    fi
fi

echo "[2/3] Beginning configuration phase..."

if [ "$REGISTER_IDENTITY" = true ]; then
    echo "Registering Git identity for user $TARGET_USER..."
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        sudo -u "$TARGET_USER" git config --global user.email "$GITHUB_EMAIL"
        sudo -u "$TARGET_USER" git config --global user.name "$GITHUB_NAME"
    else
        git config --global user.email "$GITHUB_EMAIL"
        git config --global user.name "$GITHUB_NAME"
    fi
    echo "Git identity registered successfully for user $GITHUB_NAME ($GITHUB_EMAIL)."
fi

# Generate SSH key for GitHub (if -g or --github option is used)
if [ "$GENERATE_SSH_GITHUB" = true ]; then
    SSH_PATH="${USER_HOME}/.ssh"
    KEY_PATH="${SSH_PATH}/id_ed25519_github"
    
    echo "Generating SSH key for GitHub for user $TARGET_USER at ${KEY_PATH}..."
    
    # Check if we need to use sudo
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$KEY_PATH" -N ""
    else
        ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$KEY_PATH" -N ""
    fi
    if [ $? -eq 0 ]; then
        echo "SSH key generated successfully."
    else
        echo "Error: Failed to generate SSH key. Exiting."
        exit 1
    fi

    echo "Adding generated key to the SSH agent..."
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        sudo -u "$TARGET_USER" eval "$(ssh-agent -s)"
        sudo -u "$TARGET_USER" ssh-add "$KEY_PATH"
    else
        eval "$(ssh-agent -s)"
        ssh-add "$KEY_PATH"
    fi
    if [ $? -eq 0 ]; then
        echo "Key added to agent successfully."
    else
        echo "Error: Failed to add key to agent. Exiting."
        exit 1
    fi

    echo "Configuring SSH config file for GitHub..."
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        sudo -u "$TARGET_USER" mkdir -p "${SSH_PATH}"
        sudo -u "$TARGET_USER" touch "${SSH_PATH}/config"
        sudo -u "$TARGET_USER" chmod 600 "${SSH_PATH}/config"
    else
        mkdir -p "${SSH_PATH}"
        touch "${SSH_PATH}/config"
        chmod 600 "${SSH_PATH}/config"
    fi

    # Check and add GitHub config if it doesn't exist
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        if ! sudo -u "$TARGET_USER" grep -q "Host github.com" "${SSH_PATH}/config"; then
            sudo -u "$TARGET_USER" sh -c "echo 'Host github.com' | tee -a \"${SSH_PATH}/config\""
            sudo -u "$TARGET_USER" sh -c "echo '  User git' | tee -a \"${SSH_PATH}/config\""
            sudo -u "$TARGET_USER" sh -c "echo '  IdentityFile ${KEY_PATH}' | tee -a \"${SSH_PATH}/config\""
            echo "GitHub configuration added to ~/.ssh/config."
        else
            echo "GitHub configuration already exists in ~/.ssh/config. Skipping."
        fi
    else
        if ! grep -q "Host github.com" "${SSH_PATH}/config"; then
            echo 'Host github.com' | tee -a "${SSH_PATH}/config"
            echo '  User git' | tee -a "${SSH_PATH}/config"
            echo "  IdentityFile ${KEY_PATH}" | tee -a "${SSH_PATH}/config"
            echo "GitHub configuration added to ~/.ssh/config."
        else
            echo "GitHub configuration already exists in ~/.ssh/config. Skipping."
        fi
    fi
fi

# Generate SSH key for another server (if -o or --git-host option is used)
if [ "$GENERATE_SSH_OTHER" = true ]; then
    SSH_PATH="${USER_HOME}/.ssh"
    # Extracting host name from the provided URL
    HOST_NAME=$(echo "$OTHER_SSH_HOST" | sed -E 's/.*@(.*)/\1/')
    KEY_PATH="${SSH_PATH}/id_ed25519_${HOST_NAME//./_}"
    echo "Generating SSH key for ${OTHER_SSH_HOST} for user $TARGET_USER at ${KEY_PATH}..."

    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$KEY_PATH" -N ""
    else
        ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$KEY_PATH" -N ""
    fi
    if [ $? -eq 0 ]; then
        echo "SSH key generated successfully."
    else
        echo "Error: Failed to generate SSH key. Exiting."
        exit 1
    fi

    echo "Adding generated key to the SSH agent..."
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        sudo -u "$TARGET_USER" eval "$(ssh-agent -s)"
        sudo -u "$TARGET_USER" ssh-add "$KEY_PATH"
    else
        eval "$(ssh-agent -s)"
        ssh-add "$KEY_PATH"
    fi
    if [ $? -eq 0 ]; then
        echo "Key added to agent successfully."
    else
        echo "Error: Failed to add key to agent. Exiting."
        exit 1
    fi

    echo "Configuring SSH config file for ${OTHER_SSH_HOST}..."
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        sudo -u "$TARGET_USER" mkdir -p "${SSH_PATH}"
        sudo -u "$TARGET_USER" touch "${SSH_PATH}/config"
        sudo -u "$TARGET_USER" chmod 600 "${SSH_PATH}/config"
    else
        mkdir -p "${SSH_PATH}"
        touch "${SSH_PATH}/config"
        chmod 600 "${SSH_PATH}/config"
    fi

    # Check and add other server config
    if [ "$USER" != "$TARGET_USER" ] && [ "$EUID" -eq 0 ]; then
        if ! sudo -u "$TARGET_USER" grep -q "Host ${HOST_NAME}" "${SSH_PATH}/config"; then
            sudo -u "$TARGET_USER" sh -c "echo 'Host ${HOST_NAME}' | tee -a \"${SSH_PATH}/config\""
            sudo -u "$TARGET_USER" sh -c "echo '  User ${OTHER_SSH_HOST%%@*}' | tee -a \"${SSH_PATH}/config\""
            sudo -u "$TARGET_USER" sh -c "echo '  IdentityFile ${KEY_PATH}' | tee -a \"${SSH_PATH}/config\""
            echo "Configuration for ${OTHER_SSH_HOST} added to ~/.ssh/config."
        else
            echo "Configuration for ${OTHER_SSH_HOST} already exists. Skipping."
        fi
    else
        if ! grep -q "Host ${HOST_NAME}" "${SSH_PATH}/config"; then
            echo "Host ${HOST_NAME}" | tee -a "${SSH_PATH}/config"
            echo "  User ${OTHER_SSH_HOST%%@*}" | tee -a "${SSH_PATH}/config"
            echo "  IdentityFile ${KEY_PATH}" | tee -a "${SSH_PATH}/config"
            echo "Configuration for ${OTHER_SSH_HOST} added to ~/.ssh/config."
        else
            echo "Configuration for ${OTHER_SSH_HOST} already exists. Skipping."
        fi
    fi
fi

echo "[3/3] Done"

if [ "$INSTALL_LFS" = false ] && [ "$REGISTER_IDENTITY" = false ] && [ "$GENERATE_SSH_GITHUB" = false ] && [ "$GENERATE_SSH_OTHER" = false ] && [ "$SKIP_GIT_INSTALL" = false ]; then
    echo "Script finished. Only Git has been installed."
fi

exit 0