# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_BREADCRUMB, NEEDS_REBOOT used by other sourced modules
#########################################################
# lib/advanced.sh — Advanced menu, emergency mode, startup
# Sourced by rns_management_tool.sh
#########################################################

#########################################################
# Emergency/Quick Mode - field operations
# Minimal interface for rapid deployment and status checks
#########################################################

emergency_quick_mode() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Quick Mode"
        print_breadcrumb

        # Compact status box
        print_box_top
        print_box_line "${CYAN}${BOLD}Quick Mode${NC} - Field Operations"
        print_box_divider

        if check_service_status "rnsd"; then
            print_box_line "${GREEN}●${NC} rnsd: ${GREEN}Running${NC}"
        else
            print_box_line "${RED}○${NC} rnsd: ${YELLOW}Stopped${NC}"
        fi

        if [ "$HAS_RNSTATUS" = true ] && check_service_status "rnsd"; then
            local iface_count
            iface_count=$(rnstatus 2>/dev/null | grep -c "interface" || echo "?")
            print_box_line "  Interfaces: $iface_count"
        fi

        print_box_bottom
        echo ""

        echo -e "${BOLD}Quick Actions:${NC}"
        echo ""
        echo "   1) Start rnsd daemon"
        echo "   2) Stop rnsd daemon"
        echo "   3) Network status (rnstatus)"
        echo "   4) Path table (rnpath -t)"
        echo "   5) Probe destination"
        echo "   6) Send file (rncp)"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Action: "
        read -r QM_CHOICE

        case $QM_CHOICE in
            1)
                if check_service_status "rnsd"; then
                    print_info "rnsd is already running"
                else
                    print_info "Starting rnsd..."
                    start_services
                fi
                pause_for_input
                ;;
            2)
                stop_services
                pause_for_input
                ;;
            3)
                if [ "$HAS_RNSTATUS" = true ]; then
                    rnstatus 2>&1
                else
                    print_warning "rnstatus not available"
                fi
                pause_for_input
                ;;
            4)
                if [ "$HAS_RNPATH" = true ]; then
                    rnpath -t 2>&1
                else
                    print_warning "rnpath not available"
                fi
                pause_for_input
                ;;
            5)
                if [ "$HAS_RNPROBE" = true ]; then
                    echo -n "Destination hash: "
                    read -r QM_DEST
                    if [ -n "$QM_DEST" ]; then
                        rnprobe "$QM_DEST" 2>&1
                    fi
                else
                    print_warning "rnprobe not available"
                fi
                pause_for_input
                ;;
            6)
                if [ "$HAS_RNCP" = true ]; then
                    echo -n "File to send: "
                    read -r QM_FILE
                    if [ -n "$QM_FILE" ] && [ -f "$QM_FILE" ]; then
                        echo -n "Destination hash: "
                        read -r QM_DEST
                        if [ -n "$QM_DEST" ]; then
                            rncp "$QM_FILE" "$QM_DEST" 2>&1
                        fi
                    elif [ -n "$QM_FILE" ]; then
                        print_error "File not found: $QM_FILE"
                    fi
                else
                    print_warning "rncp not available"
                fi
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
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
        echo -e "  ${CYAN}─── Configuration ───${NC}"
        echo "   1) View Configuration Files"
        echo "   2) Edit Configuration File"
        echo "   3) Apply Configuration Template"
        echo ""
        echo -e "  ${CYAN}─── Maintenance ───${NC}"
        echo "   4) Update System Packages"
        echo "   5) Reinstall All Components"
        echo "   6) Clean Cache and Temporary Files"
        echo "   7) View/Search Logs"
        echo "   8) Reset to Factory Defaults"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r ADV_CHOICE

        case $ADV_CHOICE in
            1)
                view_config_files
                pause_for_input
                ;;
            2)
                edit_config_file
                ;;
            3)
                apply_config_template
                pause_for_input
                ;;
            4)
                update_system_packages
                pause_for_input
                ;;
            5)
                print_warning "This will reinstall all Reticulum components"
                if confirm_action "Continue?"; then
                    install_reticulum_ecosystem
                fi
                pause_for_input
                ;;
            6)
                print_section "Cleaning Cache"
                print_info "Cleaning pip cache..."
                "$PIP_CMD" cache purge 2>&1 | tee -a "$UPDATE_LOG"

                if command -v npm &>/dev/null; then
                    print_info "Cleaning npm cache..."
                    npm cache clean --force 2>&1 | tee -a "$UPDATE_LOG"
                fi

                print_success "Cache cleaned"
                pause_for_input
                ;;
            7)
                view_logs_menu
                ;;
            8)
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
                    [ -d "$REAL_HOME/.reticulum" ] && rm -rf "$REAL_HOME/.reticulum" && print_success "Removed ~/.reticulum"
                    [ -d "$REAL_HOME/.nomadnetwork" ] && rm -rf "$REAL_HOME/.nomadnetwork" && print_success "Removed ~/.nomadnetwork"
                    [ -d "$REAL_HOME/.lxmf" ] && rm -rf "$REAL_HOME/.lxmf" && print_success "Removed ~/.lxmf"

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
                ;;
        esac
    done
}

update_system_packages() {
    print_section "Updating System Packages"

    echo -e "${YELLOW}Update all system packages?${NC}"
    echo "This will run: sudo apt update && sudo apt upgrade -y"
    if ! confirm_action "Proceed?" "y"; then
        print_warning "Skipping system updates"
        return 0
    fi

    print_info "Updating package lists..."
    if retry_with_backoff 3 run_with_timeout "$APT_TIMEOUT" sudo apt update 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Package lists updated"

        print_info "Upgrading packages (this may take several minutes)..."
        if retry_with_backoff 2 run_with_timeout "$APT_TIMEOUT" sudo apt upgrade -y 2>&1 | tee -a "$UPDATE_LOG"; then
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
        show_error_help "network" ""
        return 1
    fi
}

#########################################################
# Main Program Logic
#########################################################

# Startup health check (adapted from meshforge startup_health.py)
# Runs quick environment validation before entering main menu
run_startup_health_check() {
    local warnings=0

    log_message "Running startup health check..."

    # 1. Disk space check (need space for installs/backups)
    if ! check_disk_space 500 "$REAL_HOME"; then
        ((warnings++))
    fi

    # 2. Memory check
    if ! check_available_memory; then
        ((warnings++))
    fi

    # 3. PEP 668 notification (Debian 12+ restricts pip)
    if [ "$PEP668_DETECTED" = true ]; then
        log_message "PEP 668 detected: Python is externally managed (Debian 12+)"
        print_info "Python externally managed (PEP 668) - will use --break-system-packages where needed"
    fi

    # 4. SSH session notice
    if [ "$IS_SSH" = true ]; then
        log_debug "Running via SSH session"
    fi

    # 5. Git safe.directory for common paths
    ensure_git_safe_directory "$MESHCHAT_DIR"
    ensure_git_safe_directory "$SIDEBAND_DIR"

    # 6. Log directory writable
    if ! touch "$UPDATE_LOG" 2>/dev/null; then
        print_warning "Cannot write to log file: $UPDATE_LOG"
        UPDATE_LOG="/tmp/rns_management_$(date +%Y%m%d_%H%M%S).log"
        print_info "Falling back to: $UPDATE_LOG"
        ((warnings++))
    fi

    if [ $warnings -gt 0 ]; then
        log_warn "Startup health check completed with $warnings warning(s)"
    else
        log_message "Startup health check passed"
    fi

    return 0
}

# First-Run Wizard (adapted from meshforge first_run_mixin.py)
# Detects when Reticulum is not yet configured and guides the user
# through initial setup. Non-destructive - only runs when no config exists.
first_run_wizard() {
    # Only trigger if no Reticulum config exists
    if [ -f "$REAL_HOME/.reticulum/config" ]; then
        return 0
    fi

    # Check if RNS is installed at all
    local rns_installed=false
    if command -v rnsd &>/dev/null || pip3 show rns &>/dev/null 2>&1; then
        rns_installed=true
    fi

    print_header
    print_box_top
    print_box_line "${CYAN}${BOLD}Welcome to RNS Management Tool${NC}"
    print_box_line "First-time setup detected"
    print_box_bottom
    echo ""

    if [ "$rns_installed" = false ]; then
        print_info "Reticulum (RNS) is not installed yet."
        echo ""
        echo "  This wizard will help you:"
        echo "    1. Install the Reticulum network stack"
        echo "    2. Choose a configuration template"
        echo "    3. Start the rnsd daemon"
        echo ""

        if ! confirm_action "Run first-time setup?" "y"; then
            print_info "Skipping setup - you can install later from the main menu"
            return 0
        fi

        # Step 1: Prerequisites
        print_section "Step 1: Prerequisites"
        if ! check_python || ! check_pip; then
            print_info "Installing prerequisites..."
            install_prerequisites
        else
            print_success "Python and pip are available"
        fi

        # Step 2: Install RNS
        print_section "Step 2: Install Reticulum"
        install_reticulum_ecosystem
        invalidate_status_cache
    else
        print_info "Reticulum is installed but no configuration file exists."
        echo ""
        echo "  This wizard will help you:"
        echo "    1. Choose a configuration template"
        echo "    2. Start the rnsd daemon"
        echo ""

        if ! confirm_action "Run first-time setup?" "y"; then
            print_info "Skipping - rnsd will create a default config on first start"
            return 0
        fi
    fi

    # Step 3: Config template selection
    print_section "Step 3: Choose Configuration"
    echo ""
    echo "  How will you use Reticulum?"
    echo ""
    echo "   1) Local network only (simplest)"
    echo "      Discover peers on your LAN automatically"
    echo ""
    echo "   2) Connect to the wider network via internet"
    echo "      Join public transport nodes over TCP"
    echo ""
    echo "   3) LoRa radio with RNODE device"
    echo "      Off-grid communication via LoRa"
    echo ""
    echo "   4) Transport node (advanced)"
    echo "      Route traffic for other peers"
    echo ""
    echo "   5) Skip - use default config"
    echo "      rnsd will create a minimal config"
    echo ""
    echo -n "Select setup type (1-5): "
    read -r SETUP_CHOICE

    local template_dir="$SCRIPT_DIR/config_templates"
    local applied_template=false

    case $SETUP_CHOICE in
        1)
            if [ -f "$template_dir/minimal.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/minimal.conf" "$REAL_HOME/.reticulum/config"
                print_success "Minimal configuration applied"
                applied_template=true
            fi
            ;;
        2)
            if [ -f "$template_dir/tcp_client.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/tcp_client.conf" "$REAL_HOME/.reticulum/config"
                print_success "TCP client configuration applied"
                print_info "Connected to Dublin Hub by default"
                applied_template=true
            fi
            ;;
        3)
            if [ -f "$template_dir/lora_rnode.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/lora_rnode.conf" "$REAL_HOME/.reticulum/config"
                print_success "LoRa RNODE configuration applied"
                print_warning "Edit ~/.reticulum/config to set your device port and frequency"
                applied_template=true
            fi
            ;;
        4)
            if [ -f "$template_dir/transport_node.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/transport_node.conf" "$REAL_HOME/.reticulum/config"
                print_success "Transport node configuration applied"
                print_warning "Review ~/.reticulum/config before starting"
                applied_template=true
            fi
            ;;
        5|"")
            print_info "Skipping template - rnsd will create default config"
            ;;
        *)
            print_info "Skipping template - rnsd will create default config"
            ;;
    esac

    # Step 4: Start rnsd
    if [ "$applied_template" = true ] || command -v rnsd &>/dev/null; then
        echo ""
        if confirm_action "Start rnsd daemon now?" "y"; then
            start_services
        else
            print_info "Start later with: rnsd --daemon"
        fi
    fi

    echo ""
    print_success "First-time setup complete"
    log_message "First-run wizard completed (template: ${SETUP_CHOICE:-skipped})"
    pause_for_input
}
