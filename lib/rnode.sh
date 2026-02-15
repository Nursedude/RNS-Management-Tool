# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_BREADCRUMB used by other sourced modules
#########################################################
# lib/rnode.sh — RNODE device configuration and management
# Sourced by rns_management_tool.sh
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
