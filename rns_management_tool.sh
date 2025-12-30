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
SCRIPT_VERSION="2.2.0"
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

# UI Constants
BOX_WIDTH=58
MENU_BREADCRUMB=""

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

# Enhanced progress bar with colors and ETA
print_progress_bar() {
    local current=$1
    local total=$2
    local title="${3:-Progress}"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    # Color based on progress
    local bar_color="$YELLOW"
    [ $percent -ge 50 ] && bar_color="$CYAN"
    [ $percent -ge 90 ] && bar_color="$GREEN"

    printf "\r  ${title}: ${bar_color}["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "]${NC} %3d%% (%d/%d)" "$percent" "$current" "$total"
}

# Step-based progress display for multi-step operations
declare -a OPERATION_STEPS=()
CURRENT_STEP=0

init_operation() {
    local title="$1"
    shift
    OPERATION_STEPS=("$@")
    CURRENT_STEP=0

    echo ""
    print_box_top
    print_box_line "${CYAN}${BOLD}$title${NC}"
    print_box_divider

    local total=${#OPERATION_STEPS[@]}
    for ((i=0; i<total; i++)); do
        print_box_line "  ${YELLOW}○${NC} ${OPERATION_STEPS[$i]}"
    done

    print_box_bottom
    echo ""
}

next_step() {
    local status="${1:-success}"
    local total=${#OPERATION_STEPS[@]}

    if [ $CURRENT_STEP -lt $total ]; then
        if [ "$status" = "success" ]; then
            echo -e "  ${GREEN}✓${NC} ${OPERATION_STEPS[$CURRENT_STEP]}"
        elif [ "$status" = "skip" ]; then
            echo -e "  ${YELLOW}⊘${NC} ${OPERATION_STEPS[$CURRENT_STEP]} ${YELLOW}(skipped)${NC}"
        else
            echo -e "  ${RED}✗${NC} ${OPERATION_STEPS[$CURRENT_STEP]} ${RED}(failed)${NC}"
        fi
        ((CURRENT_STEP++))
    fi
}

complete_operation() {
    local status="${1:-success}"
    echo ""

    if [ "$status" = "success" ]; then
        print_success "Operation completed successfully"
    else
        print_error "Operation completed with errors"
    fi
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$UPDATE_LOG"
}

# Enhanced error display with troubleshooting suggestions
show_error_help() {
    local error_type="$1"
    local context="$2"

    echo ""
    echo -e "${RED}${BOLD}Error: $error_type${NC}"
    echo ""

    case "$error_type" in
        "network")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check your internet connection"
            echo "  2) Try: ping -c 3 google.com"
            echo "  3) Check DNS settings"
            echo "  4) If behind proxy, configure git and pip accordingly"
            ;;
        "permission")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check file/directory permissions"
            echo "  2) Try running with sudo if appropriate"
            echo "  3) Verify you own the files: ls -la $context"
            ;;
        "python")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Install Python 3.7+: sudo apt install python3 python3-pip"
            echo "  2) Check version: python3 --version"
            echo "  3) Verify pip: pip3 --version"
            ;;
        "nodejs")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Install Node.js: select option 1 to install automatically"
            echo "  2) Check version: node --version (requires 18+)"
            echo "  3) Manual install: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
            ;;
        "pip")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Upgrade pip: pip3 install --upgrade pip"
            echo "  2) Try with --user flag: pip3 install --user <package>"
            echo "  3) Clear cache: pip3 cache purge"
            echo "  4) Check for conflicts: pip3 check"
            ;;
        "git")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Install git: sudo apt install git"
            echo "  2) Check SSH keys for private repos"
            echo "  3) Try HTTPS URL instead of SSH"
            ;;
        "device")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check device is connected: ls /dev/ttyUSB* /dev/ttyACM*"
            echo "  2) Add user to dialout group: sudo usermod -aG dialout \$USER"
            echo "  3) Reconnect device and try again"
            echo "  4) Check permissions: sudo chmod 666 $context"
            ;;
        "service")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check service status: systemctl --user status rnsd"
            echo "  2) View logs: journalctl --user -u rnsd -n 50"
            echo "  3) Try manual start: rnsd --daemon"
            echo "  4) Check config: cat ~/.reticulum/config"
            ;;
        *)
            echo -e "${YELLOW}General troubleshooting:${NC}"
            echo "  1) Check log file: $UPDATE_LOG"
            echo "  2) Run diagnostics: select option 6 from main menu"
            echo "  3) Visit: https://github.com/markqvist/Reticulum/issues"
            ;;
    esac
    echo ""
}

# Validate input is numeric
validate_numeric() {
    local input="$1"
    local min="${2:-0}"
    local max="${3:-999999}"

    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; then
        return 1
    fi

    return 0
}

# Validate device port format
validate_device_port() {
    local port="$1"

    if [[ ! "$port" =~ ^/dev/tty[A-Za-z0-9]+$ ]]; then
        print_error "Invalid device port format"
        echo "Expected format: /dev/ttyUSB0 or /dev/ttyACM0"
        return 1
    fi

    if [ ! -e "$port" ]; then
        print_error "Device not found: $port"
        show_error_help "device" "$port"
        return 1
    fi

    return 0
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

# Enhanced UI Functions
print_box_line() {
    local content="$1"
    local padding=$((BOX_WIDTH - ${#content} - 4))
    [ $padding -lt 0 ] && padding=0
    printf "${BOLD}│${NC} %s%*s ${BOLD}│${NC}\n" "$content" "$padding" ""
}

print_box_top() {
    printf "${BOLD}┌"
    printf '─%.0s' $(seq 1 $BOX_WIDTH)
    printf "┐${NC}\n"
}

print_box_bottom() {
    printf "${BOLD}└"
    printf '─%.0s' $(seq 1 $BOX_WIDTH)
    printf "┘${NC}\n"
}

print_box_divider() {
    printf "${BOLD}├"
    printf '─%.0s' $(seq 1 $BOX_WIDTH)
    printf "┤${NC}\n"
}

print_breadcrumb() {
    if [ -n "$MENU_BREADCRUMB" ]; then
        echo -e "${CYAN}Location:${NC} $MENU_BREADCRUMB"
        echo ""
    fi
}

show_help() {
    print_header
    echo -e "${BOLD}Help & Quick Reference${NC}\n"
    echo -e "${CYAN}Navigation:${NC}"
    echo "  • Enter the number of your choice and press Enter"
    echo "  • Press 0 to go back or exit"
    echo "  • Press h or ? for help in most menus"
    echo ""
    echo -e "${CYAN}Key Components:${NC}"
    echo "  • ${BOLD}RNS${NC} - Reticulum Network Stack (core networking)"
    echo "  • ${BOLD}LXMF${NC} - Lightweight Extensible Message Format"
    echo "  • ${BOLD}NomadNet${NC} - Terminal-based messaging client"
    echo "  • ${BOLD}MeshChat${NC} - Web-based LXMF messaging interface"
    echo "  • ${BOLD}Sideband${NC} - Mobile/Desktop LXMF client"
    echo "  • ${BOLD}RNODE${NC} - LoRa radio hardware for long-range links"
    echo ""
    echo -e "${CYAN}Common Tasks:${NC}"
    echo "  • Start daemon:    ${GREEN}rnsd --daemon${NC}"
    echo "  • Check status:    ${GREEN}rnstatus${NC}"
    echo "  • Launch NomadNet: ${GREEN}nomadnet${NC}"
    echo "  • Configure RNODE: ${GREEN}rnodeconf --autoinstall${NC}"
    echo ""
    echo -e "${CYAN}Configuration Files:${NC}"
    echo "  • ~/.reticulum/config   - Main RNS configuration"
    echo "  • ~/.nomadnetwork/      - NomadNet settings"
    echo "  • ~/.lxmf/              - LXMF message store"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  • https://reticulum.network/"
    echo "  • https://github.com/markqvist/Reticulum"
    echo ""
    pause_for_input
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"  # Default to 'n' if not specified

    if [ "$default" = "y" ]; then
        echo -n "$message (Y/n): "
        read -r response
        [[ ! "$response" =~ ^[Nn]$ ]]
    else
        echo -n "$message (y/N): "
        read -r response
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

show_operation_summary() {
    local title="$1"
    shift
    local items=("$@")

    echo ""
    print_box_top
    print_box_line "${CYAN}${BOLD}$title${NC}"
    print_box_divider

    for item in "${items[@]}"; do
        print_box_line "  $item"
    done

    print_box_bottom
    echo ""
}

#########################################################
# Main Menu System
#########################################################

show_main_menu() {
    print_header
    MENU_BREADCRUMB=""

    # Quick status dashboard with dynamic formatting
    print_box_top
    print_box_line "${CYAN}${BOLD}Quick Status${NC}"
    print_box_divider

    # Check rnsd status
    if pgrep -f "rnsd" > /dev/null 2>&1; then
        local rnsd_status="${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC}"
    else
        local rnsd_status="${RED}○${NC} rnsd daemon: ${YELLOW}Stopped${NC}"
    fi
    print_box_line "$rnsd_status"

    # Check RNS installed
    if command -v rnstatus &> /dev/null; then
        local rns_ver
        rns_ver=$(pip3 show rns 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "?")
        print_box_line "${GREEN}●${NC} RNS: v${rns_ver}"
    else
        print_box_line "${YELLOW}○${NC} RNS: ${YELLOW}Not installed${NC}"
    fi

    # Check LXMF installed
    if pip3 show lxmf &>/dev/null; then
        local lxmf_ver
        lxmf_ver=$(pip3 show lxmf 2>/dev/null | grep "^Version:" | awk '{print $2}')
        print_box_line "${GREEN}●${NC} LXMF: v${lxmf_ver}"
    else
        print_box_line "${YELLOW}○${NC} LXMF: Not installed"
    fi

    print_box_bottom
    echo ""

    echo -e "${BOLD}Main Menu:${NC}"
    echo ""
    echo -e "  ${CYAN}─── Installation ───${NC}"
    echo "   1) Install/Update Reticulum Ecosystem"
    echo "   2) Install/Configure RNODE Device"
    echo "   3) Install NomadNet"
    echo "   4) Install MeshChat"
    echo "   5) Install Sideband"
    echo ""
    echo -e "  ${CYAN}─── Management ───${NC}"
    echo "   6) System Status & Diagnostics"
    echo "   7) Manage Services"
    echo "   8) Backup/Restore Configuration"
    echo "   9) Advanced Options"
    echo ""
    echo -e "  ${CYAN}─── Help & Exit ───${NC}"
    echo "   h) Help & Quick Reference"
    echo "   0) Exit"
    echo ""
    echo -n "Select an option: "
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
    print_header
    MENU_BREADCRUMB="Main Menu > RNODE Configuration"
    print_breadcrumb

    # Check if rnodeconf is available
    if ! command -v rnodeconf &> /dev/null; then
        print_error "rnodeconf not found"
        echo ""
        if confirm_action "Install rnodeconf now?" "y"; then
            install_rnode_tools || return 1
        else
            return 1
        fi
    fi

    echo -e "${BOLD}RNODE Configuration Wizard${NC}\n"

    # Show detected devices
    local devices
    devices=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null)
    if [ -n "$devices" ]; then
        echo -e "${GREEN}Detected USB devices:${NC}"
        echo "$devices" | while read -r dev; do
            echo "  • $dev"
        done
        echo ""
    fi

    echo -e "  ${CYAN}─── Basic Operations ───${NC}"
    echo "    1) Auto-install firmware (recommended)"
    echo "    2) List supported devices"
    echo "    3) Flash specific device"
    echo "    4) Update existing RNODE"
    echo "    5) Get device information"
    echo ""
    echo -e "  ${CYAN}─── Hardware Configuration ───${NC}"
    echo "    6) Configure radio parameters"
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
# Sideband Installation
#########################################################

install_sideband() {
    print_section "Installing Sideband"

    echo -e "${CYAN}${BOLD}About Sideband${NC}\n"
    echo "Sideband is a graphical LXMF messaging application that provides:"
    echo "  • Secure end-to-end encrypted messaging"
    echo "  • Works over any medium Reticulum supports"
    echo "  • Available for Linux, macOS, Windows, and Android"
    echo ""

    # Check Python first
    if ! check_python || ! check_pip; then
        print_error "Python 3.7+ and pip are required"
        return 1
    fi

    # Check for display (Sideband is a GUI app)
    if [ -z "$DISPLAY" ] && [ -z "$XDG_CURRENT_DESKTOP" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        print_warning "No graphical display detected"
        echo ""
        echo "Sideband requires a graphical environment to run."
        echo "On headless systems, consider using NomadNet (terminal client) instead."
        echo ""
        echo -n "Continue anyway? (y/N): "
        read -r CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    # Installation method menu
    echo -e "${BOLD}Installation Options:${NC}\n"
    echo "   1) Install via pip (recommended for Linux)"
    echo "   2) Install from source (latest development version)"
    echo "   3) Download AppImage (portable, no installation)"
    echo "   4) Show platform-specific instructions"
    echo "   0) Cancel"
    echo ""
    echo -n "Select installation method: "
    read -r INSTALL_METHOD

    case $INSTALL_METHOD in
        1)
            install_sideband_pip
            ;;
        2)
            install_sideband_source
            ;;
        3)
            download_sideband_appimage
            ;;
        4)
            show_sideband_platform_instructions
            ;;
        0|"")
            print_info "Installation cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
}

install_sideband_pip() {
    print_section "Installing Sideband via pip"

    # Check for required system dependencies
    print_info "Checking system dependencies..."

    local missing_deps=()

    # Check for required packages for GUI
    if ! dpkg -l | grep -q "python3-tk"; then
        missing_deps+=("python3-tk")
    fi
    if ! dpkg -l | grep -q "python3-pil"; then
        missing_deps+=("python3-pil" "python3-pil.imagetk")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_info "Installing required dependencies..."
        sudo apt update
        sudo apt install -y "${missing_deps[@]}" 2>&1 | tee -a "$UPDATE_LOG"
    fi

    print_info "Installing Sideband..."

    if $PIP_CMD install sbapp --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed successfully"

        # Verify installation
        if command -v sideband &> /dev/null || $PIP_CMD show sbapp &>/dev/null; then
            local sb_version
            sb_version=$($PIP_CMD show sbapp 2>/dev/null | grep "^Version:" | awk '{print $2}')
            print_success "Sideband v$sb_version is ready"
            log_message "Installed Sideband v$sb_version"

            # Create desktop launcher
            create_sideband_launcher

            echo ""
            print_info "To launch Sideband, run: ${GREEN}sideband${NC}"
        else
            print_warning "Installation completed but sideband command not found"
            print_info "Try: python3 -m sbapp"
        fi
        return 0
    else
        print_error "Failed to install Sideband"
        echo ""
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo "  1) Ensure you have Python 3.7 or newer"
        echo "  2) Try: pip3 install --user sbapp"
        echo "  3) Check internet connection"
        log_message "Sideband installation failed"
        return 1
    fi
}

install_sideband_source() {
    print_section "Installing Sideband from Source"

    if [ -d "$SIDEBAND_DIR" ]; then
        print_warning "Sideband directory already exists"
        echo -n "Update existing installation? (Y/n): "
        read -r UPDATE_EXISTING

        if [[ ! "$UPDATE_EXISTING" =~ ^[Nn]$ ]]; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
            print_info "Updating from git..."
            git pull origin main 2>&1 | tee -a "$UPDATE_LOG"
        else
            return 1
        fi
    else
        print_info "Cloning Sideband repository..."
        if git clone https://github.com/markqvist/Sideband.git "$SIDEBAND_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
        else
            print_error "Failed to clone Sideband repository"
            return 1
        fi
    fi

    print_info "Installing from source..."
    if $PIP_CMD install . --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed from source"
        create_sideband_launcher
        popd > /dev/null
        return 0
    else
        print_error "Failed to install Sideband from source"
        popd > /dev/null
        return 1
    fi
}

download_sideband_appimage() {
    print_section "Downloading Sideband AppImage"

    local appimage_url="https://github.com/markqvist/Sideband/releases/latest"

    echo -e "${YELLOW}AppImage is a portable format that runs without installation.${NC}"
    echo ""
    echo "Please visit the releases page to download the latest AppImage:"
    echo -e "  ${CYAN}$appimage_url${NC}"
    echo ""
    echo "After downloading:"
    echo "  1) Make it executable: chmod +x Sideband*.AppImage"
    echo "  2) Run it: ./Sideband*.AppImage"
    echo ""

    # Try to open browser if available
    if command -v xdg-open &> /dev/null && [ -n "$DISPLAY" ]; then
        echo -n "Open releases page in browser? (Y/n): "
        read -r OPEN_BROWSER
        if [[ ! "$OPEN_BROWSER" =~ ^[Nn]$ ]]; then
            xdg-open "$appimage_url" 2>/dev/null &
            print_success "Opened browser"
        fi
    fi
}

show_sideband_platform_instructions() {
    print_section "Platform-Specific Instructions"

    echo -e "${BOLD}Linux (Debian/Ubuntu):${NC}"
    echo "  pip3 install sbapp"
    echo "  or download the AppImage from GitHub releases"
    echo ""

    echo -e "${BOLD}Raspberry Pi:${NC}"
    echo "  pip3 install sbapp --break-system-packages"
    echo "  Note: May require extra time to build on older Pi models"
    echo ""

    echo -e "${BOLD}macOS:${NC}"
    echo "  pip3 install sbapp"
    echo "  or download the .dmg from GitHub releases"
    echo ""

    echo -e "${BOLD}Windows:${NC}"
    echo "  pip install sbapp"
    echo "  or download the .exe installer from GitHub releases"
    echo ""

    echo -e "${BOLD}Android:${NC}"
    echo "  Download from F-Droid or GitHub releases (.apk)"
    echo "  Note: Sideband is also available on Google Play"
    echo ""

    echo -e "${CYAN}GitHub Releases:${NC}"
    echo "  https://github.com/markqvist/Sideband/releases"
}

create_sideband_launcher() {
    if [ -n "$DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
        print_info "Creating desktop launcher..."

        DESKTOP_FILE="$HOME/.local/share/applications/sideband.desktop"
        mkdir -p "$HOME/.local/share/applications"

        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Sideband
Comment=LXMF Messaging Client for Reticulum
Exec=sideband
Icon=sideband
Terminal=false
Categories=Network;Communication;
Keywords=lxmf;reticulum;mesh;messaging;
EOF

        chmod +x "$DESKTOP_FILE"
        print_success "Desktop launcher created"
        log_message "Created Sideband desktop launcher"
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
# Service Management Menu
#########################################################

services_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Services"
        print_breadcrumb

        # Show current status at top
        print_box_top
        print_box_line "${CYAN}${BOLD}Service Status${NC}"
        print_box_divider

        if pgrep -f "rnsd" > /dev/null 2>&1; then
            print_box_line "${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC}"
        else
            print_box_line "${RED}○${NC} rnsd daemon: ${YELLOW}Stopped${NC}"
        fi

        # Check for meshtasticd
        if command -v meshtasticd &>/dev/null; then
            if pgrep -f "meshtasticd" > /dev/null 2>&1; then
                print_box_line "${GREEN}●${NC} meshtasticd: ${GREEN}Running${NC}"
            else
                print_box_line "${YELLOW}○${NC} meshtasticd: Stopped"
            fi
        fi

        print_box_bottom
        echo ""

        echo -e "${BOLD}Service Management:${NC}"
        echo ""
        echo "   1) Start rnsd daemon"
        echo "   2) Stop rnsd daemon"
        echo "   3) Restart rnsd daemon"
        echo "   4) View detailed status"
        echo "   5) View network statistics"
        echo "   6) Enable auto-start on boot"
        echo "   7) Disable auto-start on boot"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r SVC_CHOICE

        case $SVC_CHOICE in
            1)
                start_services
                pause_for_input
                ;;
            2)
                stop_services
                pause_for_input
                ;;
            3)
                print_info "Restarting rnsd daemon..."
                stop_services
                sleep 2
                start_services
                pause_for_input
                ;;
            4)
                show_service_status
                pause_for_input
                ;;
            5)
                print_section "Network Statistics"
                if command -v rnstatus &> /dev/null; then
                    rnstatus -a 2>&1 | head -n 50
                else
                    print_warning "rnstatus not available"
                fi
                pause_for_input
                ;;
            6)
                setup_autostart
                pause_for_input
                ;;
            7)
                disable_autostart
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

setup_autostart() {
    print_section "Setup Auto-Start"

    if [ ! -d "$HOME/.config/systemd/user" ]; then
        mkdir -p "$HOME/.config/systemd/user"
    fi

    local service_file="$HOME/.config/systemd/user/rnsd.service"

    cat > "$service_file" << 'EOF'
[Unit]
Description=Reticulum Network Stack Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/rnsd
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

    print_info "Enabling rnsd service..."
    systemctl --user daemon-reload
    systemctl --user enable rnsd.service

    print_success "Auto-start enabled for rnsd"
    print_info "Service will start automatically on login"
    log_message "Enabled rnsd auto-start"
}

disable_autostart() {
    print_section "Disable Auto-Start"

    if systemctl --user is-enabled rnsd.service &>/dev/null; then
        systemctl --user disable rnsd.service
        print_success "Auto-start disabled for rnsd"
        log_message "Disabled rnsd auto-start"
    else
        print_info "Auto-start was not enabled"
    fi
}

#########################################################
# Backup and Restore Menu
#########################################################

backup_restore_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Backup/Restore"
        print_breadcrumb

        # Show backup status
        local backup_count
        backup_count=$(find "$HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" 2>/dev/null | wc -l)

        print_box_top
        print_box_line "${CYAN}${BOLD}Backup Status${NC}"
        print_box_divider
        print_box_line "Available backups: $backup_count"

        if [ -d "$HOME/.reticulum" ]; then
            local config_size
            config_size=$(du -sh "$HOME/.reticulum" 2>/dev/null | cut -f1)
            print_box_line "Config size: $config_size"
        fi

        print_box_bottom
        echo ""

        echo -e "${BOLD}Backup & Restore:${NC}"
        echo ""
        echo "   1) Create backup"
        echo "   2) Restore from backup"
        echo "   3) List all backups"
        echo "   4) Delete old backups"
        echo "   5) Export configuration (portable)"
        echo "   6) Import configuration"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r BACKUP_CHOICE

        case $BACKUP_CHOICE in
            1)
                create_backup
                pause_for_input
                ;;
            2)
                restore_backup
                pause_for_input
                ;;
            3)
                list_all_backups
                pause_for_input
                ;;
            4)
                delete_old_backups
                pause_for_input
                ;;
            5)
                export_configuration
                pause_for_input
                ;;
            6)
                import_configuration
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

list_all_backups() {
    print_section "All Backups"

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" -print0 2>/dev/null | sort -z)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return
    fi

    echo -e "${BOLD}Found ${#backups[@]} backup(s):${NC}\n"

    for backup in "${backups[@]}"; do
        local backup_name
        backup_name=$(basename "$backup")
        local backup_date
        backup_date=$(echo "$backup_name" | sed -n 's/.*\([0-9]\{8\}_[0-9]\{6\}\).*/\1/p')
        local backup_size
        backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)

        # Format date nicely
        local formatted_date
        formatted_date=$(echo "$backup_date" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

        echo -e "  ${GREEN}●${NC} $formatted_date (Size: $backup_size)"
    done
}

delete_old_backups() {
    print_section "Delete Old Backups"

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" -print0 2>/dev/null | sort -z)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found to delete"
        return
    fi

    if [ ${#backups[@]} -le 3 ]; then
        print_info "Only ${#backups[@]} backup(s) exist. Keeping all."
        return
    fi

    echo -e "${YELLOW}This will keep the 3 most recent backups and delete older ones.${NC}"
    echo ""

    local to_delete=$((${#backups[@]} - 3))
    echo "Backups to delete: $to_delete"
    echo ""

    if confirm_action "Delete $to_delete old backup(s)?"; then
        local count=0
        for ((i=0; i<to_delete; i++)); do
            rm -rf "${backups[$i]}"
            ((count++))
        done
        print_success "Deleted $count old backup(s)"
        log_message "Deleted $count old backups"
    else
        print_info "Cancelled"
    fi
}

export_configuration() {
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
            print_success "Configuration exported to:"
            echo -e "  ${GREEN}$EXPORT_FILE${NC}"
            log_message "Exported configuration to: $EXPORT_FILE"
        else
            print_error "Failed to create export archive"
        fi

        rm -rf "$TEMP_EXPORT"
    else
        print_warning "No configuration files found to export"
    fi
}

import_configuration() {
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

        if confirm_action "Continue?"; then
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

view_config_files() {
    print_section "Configuration Files"

    echo -e "${BOLD}Available configuration files:${NC}\n"

    local configs_found=false

    if [ -f "$HOME/.reticulum/config" ]; then
        echo "   1) Reticulum config (~/.reticulum/config)"
        configs_found=true
    fi

    if [ -f "$HOME/.nomadnetwork/config" ]; then
        echo "   2) NomadNet config (~/.nomadnetwork/config)"
        configs_found=true
    fi

    if [ -f "$HOME/.lxmf/config" ]; then
        echo "   3) LXMF config (~/.lxmf/config)"
        configs_found=true
    fi

    if [ "$configs_found" = false ]; then
        print_warning "No configuration files found"
        print_info "Run rnsd --daemon to create initial Reticulum config"
        return
    fi

    echo ""
    echo "   0) Cancel"
    echo ""
    echo -n "Select file to view: "
    read -r CONFIG_CHOICE

    case $CONFIG_CHOICE in
        1)
            if [ -f "$HOME/.reticulum/config" ]; then
                print_section "Reticulum Configuration"
                echo -e "${CYAN}File: ~/.reticulum/config${NC}\n"
                cat "$HOME/.reticulum/config" | head -n 100
                if [ "$(wc -l < "$HOME/.reticulum/config")" -gt 100 ]; then
                    echo ""
                    print_info "Showing first 100 lines. Use 'cat ~/.reticulum/config' for full file."
                fi
            fi
            ;;
        2)
            if [ -f "$HOME/.nomadnetwork/config" ]; then
                print_section "NomadNet Configuration"
                echo -e "${CYAN}File: ~/.nomadnetwork/config${NC}\n"
                cat "$HOME/.nomadnetwork/config" | head -n 100
            fi
            ;;
        3)
            if [ -f "$HOME/.lxmf/config" ]; then
                print_section "LXMF Configuration"
                echo -e "${CYAN}File: ~/.lxmf/config${NC}\n"
                cat "$HOME/.lxmf/config" | head -n 100
            fi
            ;;
        0|"")
            return
            ;;
    esac
}

view_logs_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Advanced > Logs"
        print_breadcrumb

        echo -e "${BOLD}Log Viewer:${NC}\n"
        echo "   1) View recent management tool log"
        echo "   2) View rnsd daemon logs (systemd)"
        echo "   3) Search logs for keyword"
        echo "   4) List all management logs"
        echo ""
        echo "   0) Back"
        echo ""
        echo -n "Select option: "
        read -r LOG_CHOICE

        case $LOG_CHOICE in
            1)
                print_section "Recent Log Entries"
                if [ -f "$UPDATE_LOG" ]; then
                    echo -e "${CYAN}File: $UPDATE_LOG${NC}\n"
                    tail -n 50 "$UPDATE_LOG"
                else
                    # Find most recent log
                    local latest_log
                    latest_log=$(find "$HOME" -maxdepth 1 -name "rns_management_*.log" -type f 2>/dev/null | sort -r | head -1)
                    if [ -n "$latest_log" ]; then
                        echo -e "${CYAN}File: $latest_log${NC}\n"
                        tail -n 50 "$latest_log"
                    else
                        print_warning "No log files found"
                    fi
                fi
                pause_for_input
                ;;
            2)
                print_section "Daemon Logs"
                if command -v journalctl &>/dev/null; then
                    print_info "Showing recent rnsd-related log entries..."
                    echo ""
                    journalctl --user -u rnsd --no-pager -n 30 2>/dev/null || \
                        journalctl -t rnsd --no-pager -n 30 2>/dev/null || \
                        print_warning "No systemd logs found for rnsd"
                else
                    print_warning "journalctl not available"
                    print_info "Try: ps aux | grep rnsd"
                fi
                pause_for_input
                ;;
            3)
                print_section "Search Logs"
                echo -n "Enter search term: "
                read -r SEARCH_TERM
                if [ -n "$SEARCH_TERM" ]; then
                    print_info "Searching for '$SEARCH_TERM' in log files..."
                    echo ""
                    grep -r --color=always "$SEARCH_TERM" "$HOME"/rns_management_*.log 2>/dev/null || \
                        print_warning "No matches found"
                fi
                pause_for_input
                ;;
            4)
                print_section "All Management Logs"
                local log_count
                log_count=$(find "$HOME" -maxdepth 1 -name "rns_management_*.log" -type f 2>/dev/null | wc -l)

                if [ "$log_count" -gt 0 ]; then
                    echo -e "${BOLD}Found $log_count log file(s):${NC}\n"
                    find "$HOME" -maxdepth 1 -name "rns_management_*.log" -type f -printf "  %f (%s bytes, %TY-%Tm-%Td)\n" 2>/dev/null | sort -r
                    echo ""
                    print_info "Logs are in: $HOME/"
                else
                    print_warning "No log files found"
                fi
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

advanced_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Advanced Options"
        print_breadcrumb

        echo -e "${BOLD}Advanced Options:${NC}\n"
        echo "   1) Update System Packages"
        echo "   2) Reinstall All Components"
        echo "   3) Clean Cache and Temporary Files"
        echo "   4) View Configuration Files"
        echo "   5) View/Search Logs"
        echo "   6) Reset to Factory Defaults"
        echo ""
        echo "   0) Back to Main Menu"
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
                if confirm_action "Continue?"; then
                    install_reticulum_ecosystem
                fi
                pause_for_input
                ;;
            3)
                print_section "Cleaning Cache"
                print_info "Cleaning pip cache..."
                $PIP_CMD cache purge 2>&1 | tee -a "$UPDATE_LOG"

                if command -v npm &>/dev/null; then
                    print_info "Cleaning npm cache..."
                    npm cache clean --force 2>&1 | tee -a "$UPDATE_LOG"
                fi

                print_success "Cache cleaned"
                pause_for_input
                ;;
            4)
                view_config_files
                pause_for_input
                ;;
            5)
                view_logs_menu
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
            0|"")
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
                install_sideband
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
                services_menu
                ;;
            8)
                # Backup/Restore
                backup_restore_menu
                ;;
            9)
                # Advanced Options
                advanced_menu
                ;;
            h|H|\?)
                # Help
                show_help
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
                print_error "Invalid option. Press 'h' for help."
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
