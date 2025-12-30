#!/bin/bash

#########################################################
# RNS Management Tool
# Complete Reticulum Network Stack Management Solution
# For Raspberry Pi OS, Debian, Ubuntu, and WSL
#
# Features:
# - Full Reticulum ecosystem installation
# - Interactive RNODE installer and configuration
# - Automated updates and backups
# - Enhanced error handling and recovery
# - Cross-platform support
#########################################################

set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Global variables
SCRIPT_VERSION="2.1.0"
BACKUP_DIR="$HOME/.reticulum_backup_$(date +%Y%m%d_%H%M%S)"
UPDATE_LOG="$HOME/rns_management_$(date +%Y%m%d_%H%M%S).log"
MESHCHAT_DIR="$HOME/reticulum-meshchat"
NOMADNET_DIR="$HOME/NomadNet"
SIDEBAND_DIR="$HOME/Sideband"
NEEDS_REBOOT=false
IS_WSL=false
IS_RASPBERRY_PI=false
OS_TYPE=""
ARCHITECTURE=""

#########################################################
# Utility Functions
#########################################################

detect_environment() {
    # Detect WSL
    if grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
        IS_WSL=true
        OS_TYPE="WSL"
    fi

    # Detect Raspberry Pi - comprehensive check for all models
    if [ -f /proc/cpuinfo ]; then
        if grep -qiE "Raspberry Pi|BCM2|BCM27|BCM28" /proc/cpuinfo; then
            IS_RASPBERRY_PI=true
            # Get specific Pi model
            if [ -f /proc/device-tree/model ]; then
                PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
            else
                PI_MODEL=$(grep "^Model" /proc/cpuinfo | cut -d: -f2 | xargs)
            fi
        fi
    fi

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_TYPE="${NAME:-Unknown}"
        OS_VERSION="${VERSION_ID:-Unknown}"
    fi

    # Detect architecture
    ARCHITECTURE=$(uname -m)

    log_message "Environment detected: OS=$OS_TYPE, WSL=$IS_WSL, RaspberryPi=$IS_RASPBERRY_PI, Arch=$ARCHITECTURE"
}

print_header() {
    clear
    echo -e "\n${CYAN}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}║          RNS MANAGEMENT TOOL v${SCRIPT_VERSION}                 ║${NC}"
    echo -e "${CYAN}${BOLD}║     Complete Reticulum Network Stack Manager           ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════╝${NC}\n"

    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "${GREEN}Platform:${NC} Raspberry Pi ($PI_MODEL)"
    elif [ "$IS_WSL" = true ]; then
        echo -e "${GREEN}Platform:${NC} Windows Subsystem for Linux"
    else
        echo -e "${GREEN}Platform:${NC} $OS_TYPE $OS_VERSION ($ARCHITECTURE)"
    fi
    echo ""
}

print_section() {
    echo -e "\n${BLUE}${BOLD}▶ $1${NC}\n"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))

    printf "\r${CYAN}Progress:${NC} ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%% - %s" "$percent" "$message"
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$UPDATE_LOG"
}

pause_for_input() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

show_spinner() {
    local pid=$1
    local message=$2
    local spinstr='|/-\'

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] %s" "$spinstr" "$message"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\r"
    done
    printf "    \r"
}

#########################################################
# Main Menu System
#########################################################

show_main_menu() {
    print_header

    # Quick status dashboard
    echo -e "${BOLD}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│${NC}  ${CYAN}Quick Status${NC}                                           ${BOLD}│${NC}"
    echo -e "${BOLD}├─────────────────────────────────────────────────────────┤${NC}"

    # Check rnsd status inline
    if pgrep -f "rnsd" > /dev/null 2>&1; then
        echo -e "${BOLD}│${NC}  ${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC}                               ${BOLD}│${NC}"
    else
        echo -e "${BOLD}│${NC}  ${RED}○${NC} rnsd daemon: ${YELLOW}Stopped${NC}                               ${BOLD}│${NC}"
    fi

    # Check RNS installed
    if command -v rnstatus &> /dev/null; then
        RNS_V=$(pip3 show rns 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "?")
        echo -e "${BOLD}│${NC}  ${GREEN}●${NC} RNS: v${RNS_V}                                          ${BOLD}│${NC}"
    else
        echo -e "${BOLD}│${NC}  ${YELLOW}○${NC} RNS: ${YELLOW}Not installed${NC}                                 ${BOLD}│${NC}"
    fi

    echo -e "${BOLD}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${BOLD}Main Menu:${NC}"
    echo ""
    echo -e "  ${CYAN}─── Installation ───${NC}"
    echo "  1) Install/Update Reticulum Ecosystem"
    echo "  2) Install/Configure RNODE Device"
    echo "  3) Install NomadNet"
    echo "  4) Install MeshChat"
    echo "  5) Install Sideband"
    echo ""
    echo -e "  ${CYAN}─── Management ───${NC}"
    echo "  6) System Status & Diagnostics"
    echo "  7) Manage Services"
    echo "  8) Backup/Restore Configuration"
    echo "  9) Advanced Options"
    echo ""
    echo -e "  ${CYAN}─── System ───${NC}"
    echo "  0) Exit"
    echo ""
    echo -e "${YELLOW}Tip:${NC} Run option 6 for detailed system diagnostics"
    echo ""
    echo -n "Select an option [0-9]: "
    read -r MENU_CHOICE
}

#########################################################
# System Detection and Prerequisites
#########################################################

check_python() {
    print_section "Checking Python Installation"

    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

        if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 7 ]; then
            print_success "Python $PYTHON_VERSION detected"
            log_message "Python version: $PYTHON_VERSION"
            return 0
        else
            print_error "Python $PYTHON_VERSION is too old (requires 3.7+)"
            return 1
        fi
    else
        print_error "Python3 not found"
        return 1
    fi
}

check_pip() {
    print_section "Checking pip Installation"

    if command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
        if command -v pip3 &> /dev/null; then
            PIP_CMD="pip3"
        else
            PIP_CMD="pip"
        fi
        PIP_VERSION=$($PIP_CMD --version 2>&1 | awk '{print $2}')
        print_success "pip $PIP_VERSION detected"
        log_message "pip version: $PIP_VERSION"
        return 0
    else
        print_error "pip not found"
        return 1
    fi
}

install_prerequisites() {
    print_section "Installing Prerequisites"

    local packages=("python3" "python3-pip" "git" "curl" "wget" "build-essential")

    if [ "$IS_RASPBERRY_PI" = true ]; then
        packages+=("python3-dev" "libffi-dev" "libssl-dev")
    fi

    echo -e "${YELLOW}The following packages will be installed:${NC}"
    printf '  - %s\n' "${packages[@]}"
    echo ""
    echo -n "Proceed with installation? (Y/n): "
    read -r PROCEED

    if [[ "$PROCEED" =~ ^[Nn]$ ]]; then
        print_warning "Skipping prerequisites installation"
        return 1
    fi

    print_info "Updating package lists..."
    if sudo apt update 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Package lists updated"

        print_info "Installing prerequisites..."
        if sudo apt install -y "${packages[@]}" 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "Prerequisites installed successfully"
            log_message "Prerequisites installed: ${packages[*]}"
            return 0
        else
            print_error "Failed to install some prerequisites"
            return 1
        fi
    else
        print_error "Failed to update package lists"
        return 1
    fi
}

#########################################################
# Node.js Installation (Modern Method)
#########################################################

install_nodejs_modern() {
    print_section "Installing Modern Node.js"

    # Check if nodejs is already installed and up to date
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

        if [ "$NODE_MAJOR" -ge 18 ]; then
            print_success "Node.js $NODE_VERSION is already installed"

            # Update npm if needed
            NPM_VERSION=$(npm --version 2>/dev/null | cut -d. -f1)
            if [ -n "$NPM_VERSION" ] && [ "$NPM_VERSION" -lt 10 ]; then
                print_info "Updating npm to latest version..."
                sudo npm install -g npm@latest 2>&1 | tee -a "$UPDATE_LOG"
            fi
            return 0
        else
            print_warning "Node.js $NODE_VERSION is outdated, upgrading..."
        fi
    fi

    print_info "Installing Node.js 22.x LTS from NodeSource..."
    log_message "Installing Node.js from NodeSource"

    # Install curl if not present
    if ! command -v curl &> /dev/null; then
        print_info "Installing curl..."
        sudo apt install -y curl 2>&1 | tee -a "$UPDATE_LOG"
    fi

    # Install NodeSource repository for Node.js 22.x (LTS)
    if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "NodeSource repository configured"

        # Install Node.js (includes npm)
        if sudo apt install -y nodejs 2>&1 | tee -a "$UPDATE_LOG"; then
            NODE_VERSION=$(node --version)
            NPM_VERSION=$(npm --version)
            print_success "Node.js $NODE_VERSION and npm $NPM_VERSION installed"
            log_message "Installed Node.js $NODE_VERSION and npm $NPM_VERSION"
            return 0
        else
            print_error "Failed to install Node.js"
            log_message "Node.js installation failed"
            return 1
        fi
    else
        print_error "Failed to add NodeSource repository"
        print_warning "Falling back to system Node.js (may be outdated)"
        log_message "NodeSource setup failed, using system nodejs"

        # Fallback to system packages
        sudo apt update
        sudo apt install -y nodejs npm 2>&1 | tee -a "$UPDATE_LOG"

        print_warning "System Node.js installed - may be outdated"
        return 0
    fi
}

check_nodejs_version() {
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

        print_info "Node.js version: $NODE_VERSION"

        if [ "$NODE_MAJOR" -lt 18 ]; then
            print_error "Node.js version $NODE_VERSION is too old (requires 18+)"
            echo -e "${YELLOW}Would you like to upgrade Node.js now?${NC}"
            echo -n "Upgrade Node.js? (Y/n): "
            read -r UPGRADE_NODE

            if [[ ! "$UPGRADE_NODE" =~ ^[Nn]$ ]]; then
                install_nodejs_modern
                return $?
            else
                return 1
            fi
        else
            print_success "Node.js version $NODE_VERSION is compatible"
            log_message "Node.js version check passed: $NODE_VERSION"
            return 0
        fi
    else
        print_warning "Node.js not found"
        return 1
    fi
}

#########################################################
# RNODE Installation and Configuration
#########################################################

install_rnode_tools() {
    print_section "Installing RNODE Tools"

    echo -e "${CYAN}${BOLD}RNODE Installation Guide${NC}\n"
    echo "This will install the RNode configuration utility (rnodeconf)"
    echo "which allows you to:"
    echo "  • Flash RNode firmware to supported devices"
    echo "  • Configure radio parameters"
    echo "  • Test and diagnose RNODE devices"
    echo ""

    # rnodeconf is part of the rns package
    print_info "Installing/Updating RNS (includes rnodeconf)..."

    if $PIP_CMD install rns --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "RNS and rnodeconf installed successfully"

        # Verify rnodeconf is available
        if command -v rnodeconf &> /dev/null; then
            RNODECONF_VERSION=$(rnodeconf --version 2>&1 | head -1 || echo "unknown")
            print_success "rnodeconf is ready: $RNODECONF_VERSION"
            log_message "rnodeconf installed: $RNODECONF_VERSION"
            return 0
        else
            print_warning "rnodeconf installed but not in PATH"
            print_info "You may need to restart your shell or run: hash -r"
            return 0
        fi
    else
        print_error "Failed to install RNS/rnodeconf"
        log_message "RNS installation failed"
        return 1
    fi
}

configure_rnode_interactive() {
    print_section "Interactive RNODE Configuration"

    # Check if rnodeconf is available
    if ! command -v rnodeconf &> /dev/null; then
        print_error "rnodeconf not found"
        echo -e "${YELLOW}Would you like to install it now?${NC}"
        echo -n "Install rnodeconf? (Y/n): "
        read -r INSTALL_RNODE

        if [[ ! "$INSTALL_RNODE" =~ ^[Nn]$ ]]; then
            install_rnode_tools || return 1
        else
            return 1
        fi
    fi

    echo -e "${CYAN}${BOLD}RNODE Configuration Wizard${NC}\n"
    echo "What would you like to do?"
    echo ""
    echo "  ${BOLD}Basic Operations:${NC}"
    echo "    1) Auto-install firmware (easiest - recommended)"
    echo "    2) List supported devices"
    echo "    3) Flash specific device"
    echo "    4) Update existing RNODE"
    echo "    5) Get device information"
    echo ""
    echo "  ${BOLD}Hardware Configuration:${NC}"
    echo "    6) Configure radio parameters (frequency, bandwidth, power)"
    echo "    7) Set device model and platform"
    echo "    8) View/edit device EEPROM"
    echo "    9) Update bootloader (ROM)"
    echo ""
    echo "  ${BOLD}Advanced Tools:${NC}"
    echo "   10) Open serial console"
    echo "   11) Show all rnodeconf options"
    echo "    0) Back to main menu"
    echo ""
    echo -n "Select an option: "
    read -r RNODE_CHOICE

    case $RNODE_CHOICE in
        1)
            print_section "Auto-Installing RNODE Firmware"
            echo -e "${YELLOW}This will automatically detect and flash your RNODE device.${NC}"
            echo -e "${YELLOW}Make sure your device is connected via USB.${NC}"
            echo ""
            echo -n "Continue? (Y/n): "
            read -r CONTINUE

            if [[ ! "$CONTINUE" =~ ^[Nn]$ ]]; then
                print_info "Running rnodeconf --autoinstall..."
                echo ""
                rnodeconf --autoinstall 2>&1 | tee -a "$UPDATE_LOG"

                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    print_success "RNODE firmware installed successfully!"
                    log_message "RNODE autoinstall completed"
                else
                    print_error "RNODE installation failed"
                    print_info "Check the output above for errors"
                    log_message "RNODE autoinstall failed"
                fi
            fi
            ;;
        2)
            print_section "Supported RNODE Devices"
            echo -e "${CYAN}Listing supported devices...${NC}\n"
            rnodeconf --list 2>&1 | tee -a "$UPDATE_LOG"
            ;;
        3)
            print_section "Flash Specific Device"
            echo "Enter the device port (e.g., /dev/ttyUSB0, /dev/ttyACM0):"
            echo -n "Device port: "
            read -r DEVICE_PORT

            if [ -e "$DEVICE_PORT" ]; then
                print_info "Flashing device at $DEVICE_PORT..."
                rnodeconf "$DEVICE_PORT" 2>&1 | tee -a "$UPDATE_LOG"
            else
                print_error "Device not found: $DEVICE_PORT"
            fi
            ;;
        4)
            print_section "Update Existing RNODE"
            echo "Enter the device port:"
            echo -n "Device port: "
            read -r DEVICE_PORT

            if [ -e "$DEVICE_PORT" ]; then
                print_info "Updating device at $DEVICE_PORT..."
                rnodeconf "$DEVICE_PORT" --update 2>&1 | tee -a "$UPDATE_LOG"
            else
                print_error "Device not found: $DEVICE_PORT"
            fi
            ;;
        5)
            print_section "Get Device Information"
            echo "Enter the device port:"
            echo -n "Device port: "
            read -r DEVICE_PORT

            if [ -e "$DEVICE_PORT" ]; then
                print_info "Getting device information..."
                rnodeconf "$DEVICE_PORT" --info 2>&1 | tee -a "$UPDATE_LOG"
            else
                print_error "Device not found: $DEVICE_PORT"
            fi
            ;;
        6)
            print_section "Configure Radio Parameters"
            echo "Enter the device port:"
            echo -n "Device port: "
            read -r DEVICE_PORT

            # Validate device port - prevent path traversal and injection
            if [[ ! "$DEVICE_PORT" =~ ^/dev/tty[A-Za-z0-9]+$ ]]; then
                print_error "Invalid device port format. Expected: /dev/ttyUSB0 or /dev/ttyACM0"
            elif [ ! -e "$DEVICE_PORT" ]; then
                print_error "Device not found: $DEVICE_PORT"
            else
                echo ""
                echo -e "${CYAN}Radio Parameter Configuration${NC}"
                echo "Leave blank to keep current value"
                echo ""

                # Build command with optional parameters using arrays (safer than eval)
                declare -a CMD_ARGS=("$DEVICE_PORT")

                # Frequency (validate numeric input)
                echo -n "Frequency in Hz (e.g., 915000000 for 915MHz): "
                read -r FREQ
                if [ -n "$FREQ" ]; then
                    if [[ "$FREQ" =~ ^[0-9]+$ ]]; then
                        CMD_ARGS+=("--freq" "$FREQ")
                    else
                        print_warning "Invalid frequency - must be numeric. Skipping."
                    fi
                fi

                # Bandwidth (validate numeric input)
                echo -n "Bandwidth in kHz (e.g., 125, 250, 500): "
                read -r BW
                if [ -n "$BW" ]; then
                    if [[ "$BW" =~ ^[0-9]+$ ]]; then
                        CMD_ARGS+=("--bw" "$BW")
                    else
                        print_warning "Invalid bandwidth - must be numeric. Skipping."
                    fi
                fi

                # Spreading Factor (validate range 7-12)
                echo -n "Spreading Factor (7-12): "
                read -r SF
                if [ -n "$SF" ]; then
                    if [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ]; then
                        CMD_ARGS+=("--sf" "$SF")
                    else
                        print_warning "Invalid spreading factor - must be 7-12. Skipping."
                    fi
                fi

                # Coding Rate (validate range 5-8)
                echo -n "Coding Rate (5-8): "
                read -r CR
                if [ -n "$CR" ]; then
                    if [[ "$CR" =~ ^[0-9]+$ ]] && [ "$CR" -ge 5 ] && [ "$CR" -le 8 ]; then
                        CMD_ARGS+=("--cr" "$CR")
                    else
                        print_warning "Invalid coding rate - must be 5-8. Skipping."
                    fi
                fi

                # TX Power (validate reasonable dBm range)
                echo -n "TX Power in dBm (e.g., 17): "
                read -r TXP
                if [ -n "$TXP" ]; then
                    if [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ]; then
                        CMD_ARGS+=("--txp" "$TXP")
                    else
                        print_warning "Invalid TX power - must be between -10 and 30 dBm. Skipping."
                    fi
                fi

                echo ""
                print_info "Executing: rnodeconf ${CMD_ARGS[*]}"
                rnodeconf "${CMD_ARGS[@]}" 2>&1 | tee -a "$UPDATE_LOG"
            fi
            ;;
        7)
            print_section "Set Device Model and Platform"
            echo "Enter the device port:"
            echo -n "Device port: "
            read -r DEVICE_PORT

            # Validate device port
            if [[ ! "$DEVICE_PORT" =~ ^/dev/tty[A-Za-z0-9]+$ ]]; then
                print_error "Invalid device port format. Expected: /dev/ttyUSB0 or /dev/ttyACM0"
            elif [ ! -e "$DEVICE_PORT" ]; then
                print_error "Device not found: $DEVICE_PORT"
            else
                echo ""
                echo -e "${CYAN}Device Model/Platform Configuration${NC}"
                echo ""

                # Show supported models
                print_info "Run 'rnodeconf --list' to see supported models"
                echo ""

                echo -n "Model (e.g., t3s3, lora32_v2_1): "
                read -r MODEL

                echo -n "Platform (e.g., esp32, rp2040): "
                read -r PLATFORM

                # Build command with array (safer than eval)
                declare -a CMD_ARGS=("$DEVICE_PORT")

                # Validate model (alphanumeric and underscores only)
                if [ -n "$MODEL" ]; then
                    if [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]; then
                        CMD_ARGS+=("--model" "$MODEL")
                    else
                        print_warning "Invalid model name. Skipping."
                    fi
                fi

                # Validate platform (alphanumeric only)
                if [ -n "$PLATFORM" ]; then
                    if [[ "$PLATFORM" =~ ^[a-zA-Z0-9]+$ ]]; then
                        CMD_ARGS+=("--platform" "$PLATFORM")
                    else
                        print_warning "Invalid platform name. Skipping."
                    fi
                fi

                echo ""
                print_info "Executing: rnodeconf ${CMD_ARGS[*]}"
                rnodeconf "${CMD_ARGS[@]}" 2>&1 | tee -a "$UPDATE_LOG"
            fi
            ;;
        8)
            print_section "View/Edit Device EEPROM"
            echo "Enter the device port:"
            echo -n "Device port: "
            read -r DEVICE_PORT

            if [ -e "$DEVICE_PORT" ]; then
                print_info "Reading device EEPROM..."
                rnodeconf "$DEVICE_PORT" --eeprom 2>&1 | tee -a "$UPDATE_LOG"
            else
                print_error "Device not found: $DEVICE_PORT"
            fi
            ;;
        9)
            print_section "Update Bootloader (ROM)"
            echo -e "${YELLOW}WARNING: This will update the device bootloader.${NC}"
            echo -e "${YELLOW}Only proceed if you know what you're doing!${NC}"
            echo ""
            echo "Enter the device port:"
            echo -n "Device port: "
            read -r DEVICE_PORT

            if [ ! -e "$DEVICE_PORT" ]; then
                print_error "Device not found: $DEVICE_PORT"
            else
                echo -n "Are you sure you want to update the bootloader? (yes/no): "
                read -r CONFIRM

                if [ "$CONFIRM" = "yes" ]; then
                    print_info "Updating bootloader..."
                    rnodeconf "$DEVICE_PORT" --rom 2>&1 | tee -a "$UPDATE_LOG"
                else
                    print_info "Bootloader update cancelled"
                fi
            fi
            ;;
        10)
            print_section "Open Serial Console"
            echo "Enter the device port:"
            echo -n "Device port: "
            read -r DEVICE_PORT

            if [ -e "$DEVICE_PORT" ]; then
                print_info "Opening serial console for $DEVICE_PORT..."
                print_info "Press Ctrl+C to exit"
                echo ""
                rnodeconf "$DEVICE_PORT" --console 2>&1 | tee -a "$UPDATE_LOG"
            else
                print_error "Device not found: $DEVICE_PORT"
            fi
            ;;
        11)
            print_section "All RNODE Configuration Options"
            echo -e "${CYAN}Displaying full rnodeconf help...${NC}\n"
            rnodeconf --help 2>&1 | less
            ;;
        0)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac

    pause_for_input
    configure_rnode_interactive
}

#########################################################
# Component Installation Functions
#########################################################

get_installed_version() {
    local package=$1
    $PIP_CMD show "$package" 2>/dev/null | grep "^Version:" | awk '{print $2}'
}

check_package_installed() {
    local package=$1
    local display_name=$2

    VERSION=$(get_installed_version "$package")

    if [ -n "$VERSION" ]; then
        print_info "$display_name: v$VERSION (installed)"
        log_message "$display_name installed: $VERSION"
        echo "$VERSION"
        return 0
    else
        print_warning "$display_name: not installed"
        log_message "$display_name not installed"
        echo ""
        return 1
    fi
}

update_pip_package() {
    local package=$1
    local display_name=$2

    print_section "Installing/Updating $display_name"

    OLD_VERSION=$(get_installed_version "$package")

    if [ -z "$OLD_VERSION" ]; then
        print_info "Installing $display_name..."
        log_message "Installing $display_name"
    else
        print_info "Current version: $OLD_VERSION"
        print_info "Checking for updates..."
        log_message "Updating $display_name from $OLD_VERSION"
    fi

    # Try update with --break-system-packages flag (needed on newer systems)
    if $PIP_CMD install "$package" --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        NEW_VERSION=$(get_installed_version "$package")

        if [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
            print_success "$display_name updated: $OLD_VERSION → $NEW_VERSION"
            log_message "$display_name updated to $NEW_VERSION"
        else
            print_success "$display_name is up to date: $NEW_VERSION"
            log_message "$display_name already latest: $NEW_VERSION"
        fi
        return 0
    else
        print_error "Failed to install/update $display_name"
        log_message "Failed to update $display_name"

        # Offer troubleshooting
        echo -e "\n${YELLOW}Troubleshooting options:${NC}"
        echo "  1) Check internet connection"
        echo "  2) Try updating pip: pip3 install --upgrade pip"
        echo "  3) Check system requirements"

        return 1
    fi
}

install_reticulum_ecosystem() {
    print_section "Installing Reticulum Ecosystem"

    echo -e "${CYAN}This will install/update the complete Reticulum stack:${NC}"
    echo "  • RNS (Reticulum Network Stack) - Core networking"
    echo "  • LXMF - Messaging protocol layer"
    echo "  • NomadNet - Terminal messaging client (optional)"
    echo ""

    # Update components in dependency order
    local success=true

    # RNS first (core dependency)
    update_pip_package "rns" "RNS (Reticulum)" || success=false
    sleep 1

    # LXMF (depends on RNS)
    update_pip_package "lxmf" "LXMF" || success=false
    sleep 1

    # Ask about NomadNet
    echo ""
    echo -e "${YELLOW}Would you like to install NomadNet (terminal client)?${NC}"
    echo -n "Install NomadNet? (Y/n): "
    read -r INSTALL_NOMAD

    if [[ ! "$INSTALL_NOMAD" =~ ^[Nn]$ ]]; then
        update_pip_package "nomadnet" "NomadNet" || success=false
    fi

    if [ "$success" = true ]; then
        print_success "Reticulum ecosystem installation completed"
        return 0
    else
        print_error "Some components failed to install"
        return 1
    fi
}

check_meshchat_installed() {
    if [ -d "$MESHCHAT_DIR" ] && [ -f "$MESHCHAT_DIR/package.json" ]; then
        MESHCHAT_VERSION=$(grep '"version"' "$MESHCHAT_DIR/package.json" | head -1 | awk -F'"' '{print $4}')
        print_info "MeshChat: v$MESHCHAT_VERSION (installed)"
        log_message "MeshChat installed: $MESHCHAT_VERSION"
        return 0
    else
        print_warning "MeshChat: not installed"
        log_message "MeshChat not installed"
        return 1
    fi
}

install_meshchat() {
    print_section "Installing MeshChat"

    # Check for Node.js
    if ! command -v npm &> /dev/null; then
        print_warning "Node.js/npm not found"
        echo -e "${YELLOW}MeshChat requires Node.js 18+${NC}"
        echo -n "Install Node.js now? (Y/n): "
        read -r INSTALL_NODE

        if [[ ! "$INSTALL_NODE" =~ ^[Nn]$ ]]; then
            install_nodejs_modern || return 1
        else
            return 1
        fi
    else
        check_nodejs_version || return 1
    fi

    # Check for git
    if ! command -v git &> /dev/null; then
        print_info "Installing git..."
        sudo apt update && sudo apt install -y git
    fi

    print_info "Cloning MeshChat repository..."
    log_message "Installing MeshChat"

    if [ -d "$MESHCHAT_DIR" ]; then
        print_warning "MeshChat directory already exists"
        echo -n "Update existing installation? (Y/n): "
        read -r UPDATE_EXISTING

        if [[ ! "$UPDATE_EXISTING" =~ ^[Nn]$ ]]; then
            pushd "$MESHCHAT_DIR" > /dev/null || return 1
            print_info "Updating from git..."
            git pull origin main 2>&1 | tee -a "$UPDATE_LOG"
        else
            return 1
        fi
    else
        if git clone https://github.com/liamcottle/reticulum-meshchat.git "$MESHCHAT_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
            pushd "$MESHCHAT_DIR" > /dev/null || return 1
        else
            print_error "Failed to clone MeshChat repository"
            return 1
        fi
    fi

    print_info "Installing dependencies..."
    if npm install 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Dependencies installed"

        # Security audit
        print_info "Running security audit..."
        npm audit fix --audit-level=moderate 2>&1 | tee -a "$UPDATE_LOG" || true

        print_info "Building MeshChat..."
        if npm run build 2>&1 | tee -a "$UPDATE_LOG"; then
            MESHCHAT_VERSION=$(grep '"version"' package.json | head -1 | awk -F'"' '{print $4}')
            print_success "MeshChat v$MESHCHAT_VERSION installed successfully"
            log_message "MeshChat installed: $MESHCHAT_VERSION"

            # Create launcher
            create_meshchat_launcher

            popd > /dev/null
            return 0
        else
            print_error "Failed to build MeshChat"
            popd > /dev/null
            return 1
        fi
    else
        print_error "Failed to install dependencies"
        popd > /dev/null
        return 1
    fi
}

create_meshchat_launcher() {
    if [ -n "$DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
        print_info "Creating desktop launcher..."

        DESKTOP_FILE="$HOME/.local/share/applications/meshchat.desktop"
        mkdir -p "$HOME/.local/share/applications"

        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Reticulum MeshChat
Comment=LXMF messaging client for Reticulum
Exec=bash -c 'cd $MESHCHAT_DIR && npm run dev'
Icon=$MESHCHAT_DIR/icon.png
Terminal=false
Categories=Network;Communication;
EOF

        chmod +x "$DESKTOP_FILE"
        print_success "Desktop launcher created"
        log_message "Created desktop launcher"
    fi
}

#########################################################
# Service Management
#########################################################

stop_services() {
    print_section "Stopping Services"

    # Stop rnsd if running
    if pgrep -f "rnsd" > /dev/null; then
        print_info "Stopping rnsd daemon..."
        rnsd --daemon stop 2>/dev/null || pkill -f rnsd 2>/dev/null
        sleep 2
        if ! pgrep -f "rnsd" > /dev/null; then
            print_success "rnsd stopped"
            log_message "Stopped rnsd daemon"
        else
            print_warning "rnsd may still be running"
        fi
    fi

    # Check for nomadnet processes
    if pgrep -f "nomadnet" > /dev/null; then
        print_warning "NomadNet is running - please close it manually"
        echo -n "Press Enter when NomadNet is closed..."
        read -r
        log_message "User closed NomadNet manually"
    fi

    # Check for MeshChat processes
    if pgrep -f "meshchat\|electron" > /dev/null; then
        print_warning "MeshChat appears to be running - please close it manually"
        echo -n "Press Enter when MeshChat is closed..."
        read -r
        log_message "User closed MeshChat manually"
    fi

    print_success "Services stopped"
}

start_services() {
    print_section "Starting Services"

    echo -e "${YELLOW}Would you like to start the rnsd daemon?${NC}"
    echo -n "Start rnsd? (Y/n): "
    read -r START_RNSD

    if [[ ! "$START_RNSD" =~ ^[Nn]$ ]]; then
        print_info "Starting rnsd daemon..."
        if rnsd --daemon 2>&1 | tee -a "$UPDATE_LOG"; then
            sleep 2

            # Verify it's running
            if pgrep -f "rnsd" > /dev/null; then
                print_success "rnsd daemon started"
                log_message "Started rnsd daemon successfully"

                # Show status
                print_info "Network status:"
                rnstatus 2>&1 | head -n 15
            else
                print_error "rnsd failed to start"
                print_info "Try starting manually: rnsd --daemon"
            fi
        else
            print_error "Failed to start rnsd"
        fi
    fi
}

show_service_status() {
    print_section "Service Status"

    echo -e "${BOLD}Reticulum Network Status:${NC}\n"

    # Check rnsd
    if pgrep -f "rnsd" > /dev/null; then
        print_success "rnsd daemon: Running"
        if command -v rnstatus &> /dev/null; then
            echo ""
            rnstatus 2>&1 | head -n 20
        fi
    else
        print_warning "rnsd daemon: Not running"
        echo -e "  ${CYAN}Start with:${NC} rnsd --daemon"
    fi

    echo ""
    echo -e "${BOLD}Installed Components:${NC}\n"

    # Check RNS
    RNS_VER=$(get_installed_version "rns")
    if [ -n "$RNS_VER" ]; then
        print_success "RNS: v$RNS_VER"
    else
        print_warning "RNS: Not installed"
    fi

    # Check LXMF
    LXMF_VER=$(get_installed_version "lxmf")
    if [ -n "$LXMF_VER" ]; then
        print_success "LXMF: v$LXMF_VER"
    else
        print_warning "LXMF: Not installed"
    fi

    # Check NomadNet
    NOMAD_VER=$(get_installed_version "nomadnet")
    if [ -n "$NOMAD_VER" ]; then
        print_success "NomadNet: v$NOMAD_VER"
    else
        print_info "NomadNet: Not installed"
    fi

    # Check MeshChat
    if check_meshchat_installed; then
        print_success "MeshChat: v$MESHCHAT_VERSION"
    else
        print_info "MeshChat: Not installed"
    fi

    # Check rnodeconf
    if command -v rnodeconf &> /dev/null; then
        RNODE_VER=$(rnodeconf --version 2>&1 | head -1 | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' || echo "installed")
        [ -z "$RNODE_VER" ] && RNODE_VER="installed"
        print_success "rnodeconf: $RNODE_VER"
    else
        print_info "rnodeconf: Not installed"
    fi
}

#########################################################
# Backup and Restore
#########################################################

create_backup() {
    print_section "Creating Backup"

    echo -e "${YELLOW}Create backup of Reticulum configuration?${NC}"
    echo "  • ~/.reticulum/"
    echo "  • ~/.nomadnetwork/"
    echo "  • ~/.lxmf/"
    echo ""
    echo -n "Create backup? (Y/n): "
    read -r BACKUP_CHOICE

    if [[ "$BACKUP_CHOICE" =~ ^[Nn]$ ]]; then
        print_warning "Skipping backup"
        log_message "User skipped backup"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    local backed_up=false

    # Backup RNS config
    if [ -d "$HOME/.reticulum" ]; then
        if cp -r "$HOME/.reticulum" "$BACKUP_DIR/" 2>/dev/null; then
            print_success "Backed up Reticulum config"
            log_message "Backed up ~/.reticulum"
            backed_up=true
        else
            print_error "Failed to backup Reticulum config"
        fi
    fi

    # Backup NomadNet config
    if [ -d "$HOME/.nomadnetwork" ]; then
        if cp -r "$HOME/.nomadnetwork" "$BACKUP_DIR/" 2>/dev/null; then
            print_success "Backed up NomadNet config"
            log_message "Backed up ~/.nomadnetwork"
            backed_up=true
        else
            print_error "Failed to backup NomadNet config"
        fi
    fi

    # Backup LXMF config
    if [ -d "$HOME/.lxmf" ]; then
        if cp -r "$HOME/.lxmf" "$BACKUP_DIR/" 2>/dev/null; then
            print_success "Backed up LXMF config"
            log_message "Backed up ~/.lxmf"
            backed_up=true
        else
            print_error "Failed to backup LXMF config"
        fi
    fi

    if [ "$backed_up" = true ]; then
        print_success "Backup saved to: $BACKUP_DIR"
        log_message "Backup created at: $BACKUP_DIR"
        return 0
    else
        print_warning "No configuration files found to backup"
        return 1
    fi
}

restore_backup() {
    print_section "Restore Backup"

    echo -e "${YELLOW}Available backups in your home directory:${NC}\n"

    # List available backups
    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" -print0 2>/dev/null | sort -z)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return 1
    fi

    local i=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=$(echo "$backup_name" | sed -n 's/.*\([0-9]\{8\}_[0-9]\{6\}\).*/\1/p')
        echo "  $i) $backup_date"
        ((i++))
    done

    echo ""
    echo -n "Select backup to restore (0 to cancel): "
    read -r BACKUP_CHOICE

    if [ "$BACKUP_CHOICE" -eq 0 ] 2>/dev/null; then
        return 0
    fi

    if [ "$BACKUP_CHOICE" -ge 1 ] && [ "$BACKUP_CHOICE" -le ${#backups[@]} ] 2>/dev/null; then
        local selected_backup="${backups[$((BACKUP_CHOICE-1))]}"

        echo -e "${RED}${BOLD}WARNING:${NC} This will overwrite your current configuration!"
        echo -n "Continue? (y/N): "
        read -r CONFIRM

        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            print_info "Restoring from: $selected_backup"

            # Restore configs
            [ -d "$selected_backup/.reticulum" ] && cp -r "$selected_backup/.reticulum" "$HOME/"
            [ -d "$selected_backup/.nomadnetwork" ] && cp -r "$selected_backup/.nomadnetwork" "$HOME/"
            [ -d "$selected_backup/.lxmf" ] && cp -r "$selected_backup/.lxmf" "$HOME/"

            print_success "Backup restored successfully"
            log_message "Restored backup from: $selected_backup"
        fi
    else
        print_error "Invalid selection"
    fi
}

#########################################################
# Diagnostics
#########################################################

run_diagnostics() {
    print_section "System Diagnostics"

    echo -e "${BOLD}Running comprehensive system check...${NC}\n"

    # Environment info
    echo -e "${CYAN}Environment:${NC}"
    echo "  Platform: $OS_TYPE"
    echo "  Architecture: $ARCHITECTURE"
    echo "  Raspberry Pi: $IS_RASPBERRY_PI"
    echo "  WSL: $IS_WSL"
    [ "$IS_RASPBERRY_PI" = true ] && echo "  Model: $PI_MODEL"
    echo ""

    # Python check
    echo -e "${CYAN}Python Environment:${NC}"
    if check_python; then
        which python3
        python3 -c "import sys; print(f'  Executable: {sys.executable}')"
    fi
    echo ""

    # Pip check
    echo -e "${CYAN}Package Manager:${NC}"
    if check_pip; then
        which "$PIP_CMD"
    fi
    echo ""

    # Network interfaces
    echo -e "${CYAN}Network Interfaces:${NC}"
    if command -v ip &> /dev/null; then
        ip -br addr | grep -v "^lo" | while read -r line; do
            echo "  $line"
        done
    fi
    echo ""

    # USB devices (for RNODE detection)
    echo -e "${CYAN}USB Serial Devices:${NC}"
    if ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -10; then
        echo "  (Possible RNODE devices detected)"
    else
        echo "  No USB serial devices found"
    fi
    echo ""

    # Reticulum config
    if [ -f "$HOME/.reticulum/config" ]; then
        echo -e "${CYAN}Reticulum Configuration:${NC}"
        print_success "Config file exists: ~/.reticulum/config"

        if command -v rnstatus &> /dev/null; then
            echo ""
            rnstatus 2>&1 | head -n 20
        fi
    else
        print_warning "No Reticulum configuration found"
        echo "  Run 'rnsd --daemon' to create initial config"
    fi

    echo ""
}

#########################################################
# Advanced Options
#########################################################

advanced_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Advanced Options:${NC}\n"
        echo "  1) Update System Packages"
        echo "  2) Reinstall All Components"
        echo "  3) Clean Cache and Temporary Files"
        echo "  4) Export Configuration"
        echo "  5) Import Configuration"
        echo "  6) Reset to Factory Defaults"
        echo "  7) View Logs"
        echo "  0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r ADV_CHOICE

        case $ADV_CHOICE in
            1)
                update_system_packages
                pause_for_input
                ;;
            2)
                print_warning "This will reinstall all Reticulum components"
                echo -n "Continue? (y/N): "
                read -r CONFIRM
                if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                    install_reticulum_ecosystem
                fi
                pause_for_input
                ;;
            3)
                print_info "Cleaning pip cache..."
                $PIP_CMD cache purge 2>&1 | tee -a "$UPDATE_LOG"
                print_success "Cache cleaned"
                pause_for_input
                ;;
            4)
                print_section "Export Configuration"
                EXPORT_FILE="$HOME/reticulum_config_export_$(date +%Y%m%d_%H%M%S).tar.gz"

                echo -e "${YELLOW}This will create a portable backup of your configuration.${NC}"
                echo ""

                if [ -d "$HOME/.reticulum" ] || [ -d "$HOME/.nomadnetwork" ] || [ -d "$HOME/.lxmf" ]; then
                    print_info "Creating export archive..."

                    # Create temporary directory for export
                    TEMP_EXPORT=$(mktemp -d)

                    [ -d "$HOME/.reticulum" ] && cp -r "$HOME/.reticulum" "$TEMP_EXPORT/"
                    [ -d "$HOME/.nomadnetwork" ] && cp -r "$HOME/.nomadnetwork" "$TEMP_EXPORT/"
                    [ -d "$HOME/.lxmf" ] && cp -r "$HOME/.lxmf" "$TEMP_EXPORT/"

                    if tar -czf "$EXPORT_FILE" -C "$TEMP_EXPORT" . 2>&1 | tee -a "$UPDATE_LOG"; then
                        print_success "Configuration exported to: $EXPORT_FILE"
                        log_message "Exported configuration to: $EXPORT_FILE"
                    else
                        print_error "Failed to create export archive"
                    fi

                    rm -rf "$TEMP_EXPORT"
                else
                    print_warning "No configuration files found to export"
                fi
                pause_for_input
                ;;
            5)
                print_section "Import Configuration"
                echo "Enter the path to the export archive (.tar.gz):"
                echo -n "Archive path: "
                read -r IMPORT_FILE

                if [ ! -f "$IMPORT_FILE" ]; then
                    print_error "File not found: $IMPORT_FILE"
                elif [[ ! "$IMPORT_FILE" =~ \.tar\.gz$ ]]; then
                    print_error "Invalid file format. Expected .tar.gz archive"
                else
                    echo -e "${RED}${BOLD}WARNING:${NC} This will overwrite your current configuration!"
                    echo -n "Continue? (y/N): "
                    read -r CONFIRM

                    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                        print_info "Creating backup of current configuration..."
                        create_backup

                        print_info "Importing configuration..."
                        if tar -xzf "$IMPORT_FILE" -C "$HOME" 2>&1 | tee -a "$UPDATE_LOG"; then
                            print_success "Configuration imported successfully"
                            log_message "Imported configuration from: $IMPORT_FILE"
                        else
                            print_error "Failed to import configuration"
                        fi
                    else
                        print_info "Import cancelled"
                    fi
                fi
                pause_for_input
                ;;
            6)
                print_section "Reset to Factory Defaults"
                echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}${BOLD}║                      WARNING!                          ║${NC}"
                echo -e "${RED}${BOLD}║   This will DELETE all Reticulum configuration!        ║${NC}"
                echo -e "${RED}${BOLD}║   Your identities and messages will be LOST forever!   ║${NC}"
                echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo "This will remove:"
                echo "  • ~/.reticulum/     (identities, keys, config)"
                echo "  • ~/.nomadnetwork/  (NomadNet data)"
                echo "  • ~/.lxmf/          (messages)"
                echo ""
                echo -n "Type 'RESET' to confirm factory reset: "
                read -r CONFIRM

                if [ "$CONFIRM" = "RESET" ]; then
                    print_info "Creating final backup before reset..."
                    create_backup

                    print_info "Removing configuration directories..."
                    [ -d "$HOME/.reticulum" ] && rm -rf "$HOME/.reticulum" && print_success "Removed ~/.reticulum"
                    [ -d "$HOME/.nomadnetwork" ] && rm -rf "$HOME/.nomadnetwork" && print_success "Removed ~/.nomadnetwork"
                    [ -d "$HOME/.lxmf" ] && rm -rf "$HOME/.lxmf" && print_success "Removed ~/.lxmf"

                    print_success "Factory reset complete"
                    print_info "Run 'rnsd --daemon' to create fresh configuration"
                    log_message "Factory reset performed - all configurations removed"
                else
                    print_info "Reset cancelled - confirmation not received"
                fi
                pause_for_input
                ;;
            7)
                print_section "Recent Log Entries"
                if [ -f "$UPDATE_LOG" ]; then
                    tail -n 50 "$UPDATE_LOG"
                else
                    print_warning "No log file found"
                fi
                pause_for_input
                ;;
            0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

update_system_packages() {
    print_section "Updating System Packages"

    echo -e "${YELLOW}Update all system packages?${NC}"
    echo "This will run: sudo apt update && sudo apt upgrade -y"
    echo -n "Proceed? (Y/n): "
    read -r UPDATE_SYSTEM

    if [[ "$UPDATE_SYSTEM" =~ ^[Nn]$ ]]; then
        print_warning "Skipping system updates"
        return 0
    fi

    print_info "Updating package lists..."
    if sudo apt update 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Package lists updated"

        print_info "Upgrading packages (this may take several minutes)..."
        if sudo apt upgrade -y 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "System packages updated"
            log_message "System packages upgraded successfully"
            NEEDS_REBOOT=true
            return 0
        else
            print_error "Failed to upgrade packages"
            return 1
        fi
    else
        print_error "Failed to update package lists"
        return 1
    fi
}

#########################################################
# Main Program Logic
#########################################################

main() {
    # Initialize
    detect_environment
    log_message "=== RNS Management Tool Started ==="
    log_message "Version: $SCRIPT_VERSION"

    # Main menu loop
    while true; do
        show_main_menu

        case $MENU_CHOICE in
            1)
                # Install/Update Reticulum
                if ! check_python || ! check_pip; then
                    echo -e "\n${YELLOW}Prerequisites missing. Install them now?${NC}"
                    echo -n "Install prerequisites? (Y/n): "
                    read -r INSTALL_PREREQ
                    if [[ ! "$INSTALL_PREREQ" =~ ^[Nn]$ ]]; then
                        install_prerequisites
                    else
                        pause_for_input
                        continue
                    fi
                fi

                create_backup
                stop_services
                install_reticulum_ecosystem
                start_services
                pause_for_input
                ;;
            2)
                # RNODE Installation
                configure_rnode_interactive
                ;;
            3)
                # Install NomadNet
                check_python && check_pip
                update_pip_package "nomadnet" "NomadNet"
                pause_for_input
                ;;
            4)
                # Install MeshChat
                install_meshchat
                pause_for_input
                ;;
            5)
                # Install Sideband
                print_info "Sideband installation will be added in a future update"
                pause_for_input
                ;;
            6)
                # Status & Diagnostics
                run_diagnostics
                echo ""
                show_service_status
                pause_for_input
                ;;
            7)
                # Manage Services
                echo ""
                echo "  1) Start rnsd daemon"
                echo "  2) Stop rnsd daemon"
                echo "  3) Restart rnsd daemon"
                echo "  4) View service status"
                echo ""
                echo -n "Select option: "
                read -r SVC_CHOICE

                case $SVC_CHOICE in
                    1) start_services ;;
                    2) stop_services ;;
                    3) stop_services; sleep 2; start_services ;;
                    4) show_service_status ;;
                esac
                pause_for_input
                ;;
            8)
                # Backup/Restore
                echo ""
                echo "  1) Create backup"
                echo "  2) Restore backup"
                echo ""
                echo -n "Select option: "
                read -r BACKUP_OPT

                case $BACKUP_OPT in
                    1) create_backup ;;
                    2) restore_backup ;;
                esac
                pause_for_input
                ;;
            9)
                # Advanced Options
                advanced_menu
                ;;
            0)
                # Exit
                print_section "Thank You"
                echo -e "${CYAN}Thank you for using RNS Management Tool!${NC}"
                echo ""
                log_message "=== RNS Management Tool Ended ==="

                if [ "$NEEDS_REBOOT" = true ]; then
                    echo -e "${YELLOW}${BOLD}System reboot recommended${NC}"
                    echo -n "Reboot now? (y/N): "
                    read -r REBOOT_NOW
                    if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
                        sudo reboot
                    fi
                fi
                exit 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

#########################################################
# Script Entry Point
#########################################################

# Ensure we're running on a supported system
if [ "$(uname)" != "Linux" ]; then
    echo "Error: This script is designed for Linux systems"
    echo "For Windows, please use rns_management_tool.ps1"
    exit 1
fi

# Run main program
main

exit 0
