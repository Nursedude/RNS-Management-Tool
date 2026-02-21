# shellcheck shell=bash
# shellcheck disable=SC2034  # NEEDS_REBOOT, MENU_BREADCRUMB used by other sourced modules
#########################################################
# lib/install.sh — Prerequisites, ecosystem, MeshChat, Sideband
# Sourced by rns_management_tool.sh
#########################################################

#########################################################
# System Detection and Prerequisites
#########################################################

# Disk space pre-check (adapted from meshforge diagnostics)
# Returns 0 if sufficient, 1 if low, 2 if critical
check_disk_space() {
    local min_mb="${1:-500}"  # Default: 500MB minimum
    local target_path="${2:-$REAL_HOME}"

    if ! command -v df &> /dev/null; then
        log_warn "df command not available, skipping disk check"
        return 0
    fi

    local available_mb
    available_mb=$(df -m "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -z "$available_mb" ]; then
        log_warn "Could not determine disk space for $target_path"
        return 0
    fi

    log_debug "Disk space available: ${available_mb}MB at $target_path (minimum: ${min_mb}MB)"

    if [ "$available_mb" -lt 100 ]; then
        print_error "Critical: Only ${available_mb}MB disk space available (need ${min_mb}MB)"
        log_error "Critical disk space: ${available_mb}MB at $target_path"
        return 2
    elif [ "$available_mb" -lt "$min_mb" ]; then
        print_warning "Low disk space: ${available_mb}MB available (recommend ${min_mb}MB)"
        log_warn "Low disk space: ${available_mb}MB at $target_path"
        return 1
    fi

    return 0
}

# Memory pre-check (adapted from meshforge system.py check_memory)
check_available_memory() {
    if [ ! -f /proc/meminfo ]; then
        log_debug "No /proc/meminfo, skipping memory check"
        return 0
    fi

    local total_kb available_kb percent_free
    total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)

    if [ -z "$total_kb" ] || [ -z "$available_kb" ] || [ "$total_kb" -eq 0 ]; then
        log_warn "Could not parse memory info"
        return 0
    fi

    local total_mb=$((total_kb / 1024))
    local available_mb=$((available_kb / 1024))
    percent_free=$((available_kb * 100 / total_kb))

    log_debug "Memory: ${available_mb}MB free of ${total_mb}MB (${percent_free}%)"

    if [ "$percent_free" -lt 10 ]; then
        print_warning "Low memory: ${available_mb}MB free (${percent_free}%)"
        print_info "Hint: Free up memory or add swap space"
        log_warn "Low memory: ${available_mb}MB free (${percent_free}%)"
        return 1
    fi

    return 0
}

# Git safe.directory guard (adapted from meshforge install.sh)
# Prevents "dubious ownership" errors when running as root
ensure_git_safe_directory() {
    local dir="$1"
    if [ -d "$dir/.git" ] && [ "$(id -u)" -eq 0 ]; then
        git config --global --add safe.directory "$dir" 2>/dev/null || true
        log_debug "Added git safe.directory: $dir"
    fi
}

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
    if ! confirm_action "Proceed with installation?" "y"; then
        print_warning "Skipping prerequisites installation"
        return 1
    fi

    print_info "Updating package lists..."
    if retry_with_backoff 3 run_with_timeout "$APT_TIMEOUT" sudo apt update 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Package lists updated"

        print_info "Installing prerequisites..."
        if retry_with_backoff 2 run_with_timeout "$APT_TIMEOUT" sudo apt install -y "${packages[@]}" 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "Prerequisites installed successfully"
            log_message "Prerequisites installed: ${packages[*]}"
            return 0
        else
            print_error "Failed to install some prerequisites"
            return 1
        fi
    else
        print_error "Failed to update package lists (timeout after ${APT_TIMEOUT}s)"
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
        run_with_timeout "$APT_TIMEOUT" sudo apt install -y curl 2>&1 | tee -a "$UPDATE_LOG"
    fi

    # Install NodeSource repository for Node.js 22.x (LTS) - with retry
    # Download to temp file first to avoid executing a partial/corrupt download
    local nodesource_script
    nodesource_script=$(mktemp "${TMPDIR:-/tmp}/nodesource_setup_XXXXXX.sh")
    if retry_with_backoff 3 run_with_timeout "$NETWORK_TIMEOUT" curl -fsSL -o "$nodesource_script" https://deb.nodesource.com/setup_22.x && \
       [ -s "$nodesource_script" ] && \
       sudo -E bash "$nodesource_script" 2>&1 | tee -a "$UPDATE_LOG"; then
        rm -f "$nodesource_script"
        print_success "NodeSource repository configured"

        # Install Node.js (includes npm)
        if run_with_timeout "$APT_TIMEOUT" sudo apt install -y nodejs 2>&1 | tee -a "$UPDATE_LOG"; then
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
        rm -f "$nodesource_script"
        print_error "Failed to add NodeSource repository"
        print_warning "Falling back to system Node.js (may be outdated)"
        log_message "NodeSource setup failed, using system nodejs"

        # Fallback to system packages
        run_with_timeout "$APT_TIMEOUT" sudo apt update
        run_with_timeout "$APT_TIMEOUT" sudo apt install -y nodejs npm 2>&1 | tee -a "$UPDATE_LOG"

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
            if confirm_action "Upgrade Node.js now?" "y"; then
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

    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install rns --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
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

#########################################################
# RNODE Helper Functions (Decomposed for maintainability)
#########################################################

# Helper: Prompt and validate device port
rnode_get_device_port() {
    echo "Enter the device port (e.g., /dev/ttyUSB0, /dev/ttyACM0):"
    echo -n "Device port: "
    read -r DEVICE_PORT

    # RNS002: Device port validation
    if [[ ! "$DEVICE_PORT" =~ ^/dev/tty[A-Za-z0-9]+$ ]]; then
        print_error "Invalid device port format. Expected: /dev/ttyUSB0 or /dev/ttyACM0"
        return 1
    fi

    if [ ! -e "$DEVICE_PORT" ]; then
        print_error "Device not found: $DEVICE_PORT"
        return 1
    fi

    echo "$DEVICE_PORT"
    return 0
}

# RNODE: Auto-install firmware
rnode_autoinstall() {
    print_section "Auto-Installing RNODE Firmware"
    echo -e "${YELLOW}This will automatically detect and flash your RNODE device.${NC}"
    echo -e "${YELLOW}Make sure your device is connected via USB.${NC}"
    echo ""

    if confirm_action "Continue?" "y"; then
        print_info "Running rnodeconf --autoinstall..."
        echo ""
        rnodeconf --autoinstall 2>&1 | tee -a "$UPDATE_LOG"

        if [ "${PIPESTATUS[0]}" -eq 0 ]; then
            print_success "RNODE firmware installed successfully!"
            log_message "RNODE autoinstall completed"
        else
            print_error "RNODE installation failed"
            print_info "Check the output above for errors"
            log_message "RNODE autoinstall failed"
        fi
    fi
}

# RNODE: List supported devices
rnode_list_devices() {
    print_section "Supported RNODE Devices"
    echo -e "${CYAN}Listing supported devices...${NC}\n"
    rnodeconf --list 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Flash specific device
rnode_flash_device() {
    print_section "Flash Specific Device"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Flashing device at $device_port..."
    rnodeconf "$device_port" 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Update existing device
rnode_update_device() {
    print_section "Update Existing RNODE"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Updating device at $device_port..."
    rnodeconf "$device_port" --update 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Get device information
rnode_get_info() {
    print_section "Get Device Information"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Getting device information..."
    rnodeconf "$device_port" --info 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Configure radio parameters
rnode_configure_radio() {
    print_section "Configure Radio Parameters"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    echo ""
    echo -e "${CYAN}Radio Parameter Configuration${NC}"
    echo "Leave blank to keep current value"
    echo ""

    # Build command with optional parameters using arrays (safer than eval)
    declare -a CMD_ARGS=("$device_port")

    # RNS003: Numeric range validation for all parameters
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
}

# RNODE: Set device model and platform
rnode_set_model() {
    print_section "Set Device Model and Platform"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    echo ""
    echo -e "${CYAN}Device Model/Platform Configuration${NC}"
    echo ""
    print_info "Run 'rnodeconf --list' to see supported models"
    echo ""

    echo -n "Model (e.g., t3s3, lora32_v2_1): "
    read -r MODEL

    echo -n "Platform (e.g., esp32, rp2040): "
    read -r PLATFORM

    # Build command with array (safer than eval)
    declare -a CMD_ARGS=("$device_port")

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
}

# RNODE: View/edit EEPROM
rnode_eeprom() {
    print_section "View/Edit Device EEPROM"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Reading device EEPROM..."
    rnodeconf "$device_port" --eeprom 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Update bootloader
rnode_bootloader() {
    print_section "Update Bootloader (ROM)"
    echo -e "${YELLOW}WARNING: This will update the device bootloader.${NC}"
    echo -e "${YELLOW}Only proceed if you know what you're doing!${NC}"
    echo ""

    local device_port
    device_port=$(rnode_get_device_port) || return 1

    # RNS005: Confirmation for destructive actions
    if confirm_action "Are you sure you want to update the bootloader?"; then
        print_info "Updating bootloader..."
        rnodeconf "$device_port" --rom 2>&1 | tee -a "$UPDATE_LOG"
    else
        print_info "Bootloader update cancelled"
    fi
}

# RNODE: Open serial console
rnode_serial_console() {
    print_section "Open Serial Console"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Opening serial console for $device_port..."
    print_info "Press Ctrl+C to exit"
    echo ""
    rnodeconf "$device_port" --console 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Show help
rnode_show_help() {
    print_section "All RNODE Configuration Options"
    echo -e "${CYAN}Displaying full rnodeconf help...${NC}\n"
    rnodeconf --help 2>&1 | less
}

#########################################################
# RNODE Interactive Menu (Dispatcher)
#########################################################

configure_rnode_interactive() {
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

    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > RNODE Configuration"
        print_breadcrumb

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
            1)  rnode_autoinstall ;;
            2)  rnode_list_devices ;;
            3)  rnode_flash_device ;;
            4)  rnode_update_device ;;
            5)  rnode_get_info ;;
            6)  rnode_configure_radio ;;
            7)  rnode_set_model ;;
            8)  rnode_eeprom ;;
            9)  rnode_bootloader ;;
            10) rnode_serial_console ;;
            11) rnode_show_help ;;
            0)  return 0 ;;
            *)  print_error "Invalid option" ;;
        esac

        pause_for_input
    done
}

#########################################################
# Component Installation Functions
#########################################################

get_installed_version() {
    local package=$1
    local pip="${PIP_CMD:-pip3}"
    "$pip" show "$package" 2>/dev/null | grep "^Version:" | awk '{print $2}'
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

    # Try update with --break-system-packages flag (needed on newer systems) - with retry
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install "$package" --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
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

    # Ask about NomadNet upfront so progress steps are accurate
    local install_nomad=false
    if confirm_action "Include NomadNet (terminal client)?" "y"; then
        install_nomad=true
    fi

    # Step-based progress display (wire up dead code from meshforge pattern)
    if [ "$install_nomad" = true ]; then
        init_operation "Installing Reticulum Ecosystem" \
            "Install/update RNS (core)" \
            "Verify RNS installation" \
            "Install/update LXMF" \
            "Verify LXMF installation" \
            "Install/update NomadNet" \
            "Verify NomadNet installation"
    else
        init_operation "Installing Reticulum Ecosystem" \
            "Install/update RNS (core)" \
            "Verify RNS installation" \
            "Install/update LXMF" \
            "Verify LXMF installation"
    fi

    local success=true

    # RNS first (core dependency) - with retry
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install rns --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
        # Verify RNS installation (meshforge post-install verify pattern)
        if python3 -c "import RNS; print(f'RNS {RNS.__version__}')" 2>/dev/null; then
            next_step "success"
        else
            next_step "fail"
            print_warning "RNS installed but import verification failed"
            success=false
        fi
    else
        next_step "fail"
        next_step "skip"
        success=false
    fi

    # LXMF (depends on RNS) - with retry
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install lxmf --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
        # Verify LXMF installation
        if python3 -c "import LXMF; print(f'LXMF {LXMF.__version__}')" 2>/dev/null; then
            next_step "success"
        else
            next_step "fail"
            print_warning "LXMF installed but import verification failed"
            success=false
        fi
    else
        next_step "fail"
        next_step "skip"
        success=false
    fi

    # NomadNet (optional)
    if [ "$install_nomad" = true ]; then
        if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install nomadnet --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
            next_step "success"
            if python3 -c "import nomadnet" 2>/dev/null; then
                next_step "success"
            else
                next_step "fail"
                print_warning "NomadNet installed but import verification failed"
            fi
        else
            next_step "fail"
            next_step "skip"
            success=false
        fi
    fi

    # Invalidate version cache so dashboard refreshes
    invalidate_status_cache

    if [ "$success" = true ]; then
        complete_operation "success"
        return 0
    else
        complete_operation "fail"
        show_error_help "pip" ""
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

    # Disk space pre-check (MeshChat clone + npm install needs ~500MB)
    if ! check_disk_space 500 "$REAL_HOME"; then
        print_error "Insufficient disk space for MeshChat installation"
        return 1
    fi

    # Check for Node.js
    if ! command -v npm &> /dev/null; then
        print_warning "Node.js/npm not found"
        echo -e "${YELLOW}MeshChat requires Node.js 18+${NC}"
        if confirm_action "Install Node.js now?" "y"; then
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
        run_with_timeout "$APT_TIMEOUT" sudo apt update && run_with_timeout "$APT_TIMEOUT" sudo apt install -y git
    fi

    log_message "Installing MeshChat"
    local is_update=false

    if [ -d "$MESHCHAT_DIR" ]; then
        print_warning "MeshChat directory already exists"
        if confirm_action "Update existing installation?" "y"; then
            is_update=true
        else
            return 1
        fi
    fi

    # Step-based progress (wiring up init_operation from meshforge pattern)
    init_operation "Installing MeshChat" \
        "Clone/update repository" \
        "Install npm dependencies" \
        "Security audit" \
        "Build application" \
        "Verify installation"

    # Step 1: Clone or update
    if [ "$is_update" = true ]; then
        pushd "$MESHCHAT_DIR" > /dev/null || return 1
        ensure_git_safe_directory "$MESHCHAT_DIR"
        if retry_with_backoff 3 run_with_timeout "$GIT_TIMEOUT" git pull origin main 2>&1 | tee -a "$UPDATE_LOG"; then
            next_step "success"
        else
            next_step "fail"
            popd > /dev/null || true
            complete_operation "fail"
            return 1
        fi
    else
        if retry_with_backoff 3 run_with_timeout "$GIT_TIMEOUT" git clone https://github.com/liamcottle/reticulum-meshchat.git "$MESHCHAT_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
            pushd "$MESHCHAT_DIR" > /dev/null || return 1
            next_step "success"
        else
            next_step "fail"
            print_error "Failed to clone MeshChat repository"
            complete_operation "fail"
            show_error_help "git" ""
            return 1
        fi
    fi

    # Step 2: npm install (with retry)
    if retry_with_backoff 2 run_with_timeout "$NETWORK_TIMEOUT" npm install 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
    else
        next_step "fail"
        popd > /dev/null || true
        complete_operation "fail"
        show_error_help "nodejs" ""
        return 1
    fi

    # Step 3: Security audit (non-fatal)
    npm audit fix --audit-level=moderate 2>&1 | tee -a "$UPDATE_LOG" || true
    next_step "success"

    # Step 4: Build
    if npm run build 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
    else
        next_step "fail"
        popd > /dev/null || true
        complete_operation "fail"
        return 1
    fi

    # Step 5: Verify installation
    if [ -f "package.json" ]; then
        MESHCHAT_VERSION=$(grep '"version"' package.json | head -1 | awk -F'"' '{print $4}')
        print_success "MeshChat v$MESHCHAT_VERSION installed successfully"
        log_message "MeshChat installed: $MESHCHAT_VERSION"
        create_meshchat_launcher
        next_step "success"
    else
        next_step "fail"
    fi

    popd > /dev/null || true
    complete_operation "success"
    return 0
}

# Unified desktop launcher creator (merges meshchat + sideband patterns)
# Usage: create_desktop_launcher <filename> <name> <comment> <exec> <icon> [extra_keys]
create_desktop_launcher() {
    local filename="$1" name="$2" comment="$3" exec_cmd="$4" icon="$5" extra_keys="$6"

    if [ -z "$DISPLAY" ] && [ -z "$XDG_CURRENT_DESKTOP" ]; then
        return 0
    fi

    print_info "Creating desktop launcher for $name..."

    local desktop_file="$REAL_HOME/.local/share/applications/${filename}.desktop"
    mkdir -p "$REAL_HOME/.local/share/applications"

    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$comment
Exec=$exec_cmd
Icon=$icon
Terminal=false
Categories=Network;Communication;
${extra_keys}
EOF

    chmod +x "$desktop_file"
    print_success "Desktop launcher created"
    log_message "Created $name desktop launcher"
}

create_meshchat_launcher() {
    create_desktop_launcher "meshchat" \
        "Reticulum MeshChat" \
        "LXMF messaging client for Reticulum" \
        "bash -c 'cd $MESHCHAT_DIR && npm run dev'" \
        "$MESHCHAT_DIR/icon.png"
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
        if ! confirm_action "Continue anyway?"; then
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
        run_with_timeout "$APT_TIMEOUT" sudo apt update
        run_with_timeout "$APT_TIMEOUT" sudo apt install -y "${missing_deps[@]}" 2>&1 | tee -a "$UPDATE_LOG"
    fi

    print_info "Installing Sideband..."

    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install sbapp --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed successfully"

        # Verify installation
        if command -v sideband &> /dev/null || "$PIP_CMD" show sbapp &>/dev/null; then
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
        if confirm_action "Update existing installation?" "y"; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
            print_info "Updating from git..."
            git pull origin main 2>&1 | tee -a "$UPDATE_LOG"
        else
            return 1
        fi
    else
        print_info "Cloning Sideband repository..."
        if run_with_timeout "$GIT_TIMEOUT" git clone https://github.com/markqvist/Sideband.git "$SIDEBAND_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
        else
            print_error "Failed to clone Sideband repository"
            return 1
        fi
    fi

    print_info "Installing from source..."
    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install . --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed from source"
        create_sideband_launcher
        popd > /dev/null || true
        return 0
    else
        print_error "Failed to install Sideband from source"
        popd > /dev/null || true
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
        if confirm_action "Open releases page in browser?" "y"; then
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
    create_desktop_launcher "sideband" \
        "Sideband" \
        "LXMF Messaging Client for Reticulum" \
        "sideband" \
        "sideband" \
        "Keywords=lxmf;reticulum;mesh;messaging;"
}
