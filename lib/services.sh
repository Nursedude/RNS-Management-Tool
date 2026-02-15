# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_BREADCRUMB used by other sourced modules
#########################################################
# lib/services.sh — Service management, meshtasticd, autostart
# Sourced by rns_management_tool.sh
#########################################################

#########################################################
# Service Management
#########################################################

stop_services() {
    print_section "Stopping Services"

    # Stop rnsd if running (improved detection from meshforge service_menu_mixin.py)
    if is_rnsd_running; then
        print_info "Stopping rnsd daemon..."
        rnsd --daemon stop 2>/dev/null || pkill -x rnsd 2>/dev/null

        # Poll with timeout instead of hardcoded sleep (meshforge pattern)
        local wait_count=0
        local max_wait=10
        while is_rnsd_running && [ $wait_count -lt $max_wait ]; do
            sleep 1
            ((wait_count++))
        done

        if ! is_rnsd_running; then
            print_success "rnsd stopped"
            log_message "Stopped rnsd daemon"
        else
            print_warning "rnsd may still be running after ${max_wait}s"
            log_warn "rnsd did not stop within ${max_wait}s"
        fi
    else
        print_info "rnsd is not running"
    fi

    # Check for nomadnet processes (centralized service check)
    if check_service_status "nomadnet"; then
        print_warning "NomadNet is running - please close it manually"
        echo -n "Press Enter when NomadNet is closed..."
        read -r
        log_message "User closed NomadNet manually"
    fi

    # Check for MeshChat processes (centralized service check)
    if check_service_status "meshchat"; then
        print_warning "MeshChat appears to be running - please close it manually"
        echo -n "Press Enter when MeshChat is closed..."
        read -r
        log_message "User closed MeshChat manually"
    fi

    # Invalidate status cache after service changes
    invalidate_status_cache
    print_success "Services stopped"
}

start_services() {
    print_section "Starting Services"

    if confirm_action "Start the rnsd daemon?" "y"; then
        print_info "Starting rnsd daemon..."
        if rnsd --daemon 2>&1 | tee -a "$UPDATE_LOG"; then
            # Poll with timeout instead of hardcoded sleep (meshforge pattern)
            local wait_count=0
            local max_wait=10
            while ! is_rnsd_running && [ $wait_count -lt $max_wait ]; do
                sleep 1
                ((wait_count++))
            done

            # Verify it's running
            if is_rnsd_running; then
                print_success "rnsd daemon started"
                log_message "Started rnsd daemon successfully"

                # Show status
                print_info "Network status:"
                rnstatus 2>&1 | head -n 15
            else
                print_error "rnsd failed to start after ${max_wait}s"
                show_error_help "service" ""
            fi
        else
            print_error "Failed to start rnsd"
            show_error_help "service" ""
        fi
    fi

    # Invalidate status cache after service changes
    invalidate_status_cache
}

show_service_status() {
    print_section "Service Status"

    echo -e "${BOLD}Reticulum Network Status:${NC}\n"

    # Check rnsd (using improved detection)
    if is_rnsd_running; then
        print_success "rnsd daemon: Running"
        if command -v rnstatus &> /dev/null; then
            echo ""
            rnstatus 2>&1 | head -n 20
        fi
    else
        print_warning "rnsd daemon: Not running"
        echo -e "  ${CYAN}Start with:${NC} rnsd --daemon"
    fi

    # meshtasticd status with HTTP API check (ported from meshforge)
    if command -v meshtasticd &>/dev/null; then
        echo ""
        echo -e "${BOLD}meshtasticd:${NC}"
        if check_service_status "meshtasticd"; then
            local mtd_ver
            mtd_ver=$(meshtasticd --version 2>&1 | head -1 || echo "unknown")
            print_success "meshtasticd: Running ($mtd_ver)"

            if check_meshtasticd_http_api; then
                print_success "HTTP API: $MESHTASTICD_HTTP_URL"
            else
                print_warning "HTTP API: Not reachable"
                local hint
                hint=$(check_meshtasticd_webserver_config)
                echo -e "  ${YELLOW}${hint}${NC}"
            fi
        else
            print_warning "meshtasticd: Installed but not running"
            echo -e "  ${CYAN}Start with:${NC} sudo systemctl start meshtasticd"
        fi
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
# Service Management Menu - Helper Functions
#########################################################

# Display the service status box at the top of the services menu
show_services_status_box() {
    print_box_top
    print_box_line "${CYAN}${BOLD}Service Status${NC}"
    print_box_divider

    local svc_rnsd_state svc_uptime
    svc_rnsd_state=$(get_cached_rnsd_status)
    if [ "$svc_rnsd_state" = "running" ]; then
        svc_uptime=$(get_rnsd_uptime)
        if [ -n "$svc_uptime" ]; then
            print_box_line "${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC} (up ${svc_uptime})"
        else
            print_box_line "${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC}"
        fi
        # Boot persistence warning (meshforge pattern)
        if command -v systemctl &>/dev/null; then
            if ! systemctl --user is-enabled rnsd.service &>/dev/null 2>&1; then
                print_box_line "  ${YELLOW}! not enabled at boot${NC}"
            fi
        fi
    else
        print_box_line "${RED}○${NC} rnsd daemon: ${YELLOW}Stopped${NC}"
    fi

    # Check for meshtasticd with HTTP API status (ported from meshforge)
    if command -v meshtasticd &>/dev/null; then
        if check_service_status "meshtasticd"; then
            print_box_line "${GREEN}●${NC} meshtasticd: ${GREEN}Running${NC}"
            if check_meshtasticd_http_api; then
                print_box_line "  ${GREEN}●${NC} HTTP API: ${GREEN}${MESHTASTICD_HTTP_URL}${NC}"
            else
                print_box_line "  ${YELLOW}!${NC} HTTP API: ${YELLOW}Not reachable${NC}"
            fi
        else
            print_box_line "${YELLOW}○${NC} meshtasticd: Stopped"
        fi
    fi

    print_box_bottom
    echo ""
}

# Handle network tools submenu (rnstatus, rnpath, rnprobe, rncp, rnx)
handle_network_tools() {
    local tool_choice="$1"

    case $tool_choice in
        5)
            print_section "Network Statistics"
            if [ "$HAS_RNSTATUS" = true ]; then
                rnstatus -a 2>&1 | head -n 50
            else
                print_warning "rnstatus not available - install RNS first"
            fi
            ;;
        6)
            print_section "Path Table"
            if [ "$HAS_RNPATH" = true ]; then
                print_info "Known paths in the Reticulum network:"
                echo ""
                rnpath -t 2>&1
            else
                print_warning "rnpath not available - install RNS first"
            fi
            ;;
        7)
            print_section "Probe Destination"
            if [ "$HAS_RNPROBE" = true ]; then
                echo -n "Enter destination hash to probe: "
                read -r PROBE_DEST
                if [ -n "$PROBE_DEST" ]; then
                    print_info "Probing $PROBE_DEST..."
                    rnprobe "$PROBE_DEST" 2>&1
                else
                    print_info "Cancelled"
                fi
            else
                print_warning "rnprobe not available - install RNS first"
            fi
            ;;
        8)
            handle_file_transfer
            ;;
        9)
            handle_remote_command
            ;;
    esac
}

# Handle rncp file transfer interactive submenu
handle_file_transfer() {
    print_section "File Transfer (rncp)"
    if [ "$HAS_RNCP" != true ]; then
        print_warning "rncp not available - install RNS first"
        return
    fi

    echo -e "${BOLD}RNS File Transfer:${NC}"
    echo ""
    echo "  ${CYAN}Send a file:${NC}"
    echo "    rncp /path/to/file <destination_hash>"
    echo ""
    echo "  ${CYAN}Receive files (listen mode):${NC}"
    echo "    rncp -l [-s /save/path]"
    echo ""
    echo "  ${CYAN}Fetch a file from remote:${NC}"
    echo "    rncp -f <filename> <destination_hash>"
    echo ""
    echo -e "${BOLD}Actions:${NC}"
    echo "   s) Send a file now"
    echo "   l) Start listening for incoming files"
    echo "   0) Cancel"
    echo ""
    echo -n "Select action: "
    read -r RNCP_ACTION
    case $RNCP_ACTION in
        s|S)
            echo -n "File path to send: "
            read -r RNCP_FILE
            if [ -z "$RNCP_FILE" ]; then
                print_info "Cancelled"
            elif [ ! -f "$RNCP_FILE" ]; then
                print_error "File not found: $RNCP_FILE"
            else
                echo -n "Destination hash: "
                read -r RNCP_DEST
                if [ -n "$RNCP_DEST" ]; then
                    print_info "Sending $RNCP_FILE to $RNCP_DEST..."
                    rncp "$RNCP_FILE" "$RNCP_DEST" 2>&1
                else
                    print_info "Cancelled"
                fi
            fi
            ;;
        l|L)
            print_info "Listening for incoming file transfers..."
            print_info "Press Ctrl+C to stop listening"
            rncp -l -s "$REAL_HOME/Downloads" 2>&1 || true
            ;;
        *)
            print_info "Cancelled"
            ;;
    esac
}

# Handle rnx remote command interactive submenu
handle_remote_command() {
    print_section "Remote Command (rnx)"
    if [ "$HAS_RNX" != true ]; then
        print_warning "rnx not available - install RNS first"
        return
    fi

    echo -e "${BOLD}RNS Remote Execution:${NC}"
    echo ""
    echo "  ${CYAN}Run a remote command:${NC}"
    echo "    rnx <destination_hash> \"command\""
    echo ""
    echo "  ${CYAN}Listen for commands:${NC}"
    echo "    rnx -l [-i identity_file]"
    echo ""
    echo -e "${YELLOW}Note: Remote must be running rnx in listen mode${NC}"
    echo ""
    echo -n "Destination hash (or 0 to cancel): "
    read -r RNX_DEST
    if [ -n "$RNX_DEST" ] && [ "$RNX_DEST" != "0" ]; then
        echo -n "Command to execute: "
        read -r RNX_CMD
        if [ -n "$RNX_CMD" ]; then
            print_info "Executing on $RNX_DEST: $RNX_CMD"
            rnx "$RNX_DEST" "$RNX_CMD" 2>&1
        else
            print_info "Cancelled"
        fi
    else
        print_info "Cancelled"
    fi
}

# Handle rnid identity management interactive submenu
handle_identity_management() {
    print_section "Identity Management (rnid)"
    if [ "$HAS_RNID" != true ]; then
        print_warning "rnid not available - install RNS first"
        return
    fi

    echo -e "${BOLD}RNS Identity Management:${NC}"
    echo ""
    echo "   1) Show my identity hash"
    echo "   2) Generate new identity"
    echo "   3) View identity file info"
    echo "   0) Cancel"
    echo ""
    echo -n "Select action: "
    read -r RNID_ACTION
    case $RNID_ACTION in
        1)
            print_info "Default identity hash:"
            rnid 2>&1
            ;;
        2)
            echo -n "Output path (default: ~/.reticulum/identities/new): "
            read -r RNID_PATH
            if [ -z "$RNID_PATH" ]; then
                if ! mkdir -p "$REAL_HOME/.reticulum/identities" 2>/dev/null; then
                    print_error "Cannot create identities directory"
                    return 1
                fi
                RNID_PATH="$REAL_HOME/.reticulum/identities/new_$(date +%Y%m%d_%H%M%S)"
            fi
            print_info "Generating new identity..."
            rnid -g "$RNID_PATH" 2>&1
            if [ -f "$RNID_PATH" ]; then
                print_success "Identity generated: $RNID_PATH"
            fi
            ;;
        3)
            echo -n "Identity file path: "
            read -r RNID_FILE
            if [ -n "$RNID_FILE" ] && [ -f "$RNID_FILE" ]; then
                rnid -i "$RNID_FILE" 2>&1
            elif [ -n "$RNID_FILE" ]; then
                print_error "File not found: $RNID_FILE"
            else
                print_info "Cancelled"
            fi
            ;;
        *)
            print_info "Cancelled"
            ;;
    esac
}

# Start meshtasticd service (ported from meshforge/reticulum_updater.sh)
meshtasticd_start() {
    print_section "Starting meshtasticd"
    if ! command -v meshtasticd &>/dev/null; then
        print_error "meshtasticd is not installed"
    elif check_service_status "meshtasticd"; then
        print_info "meshtasticd is already running"
    else
        print_info "Starting meshtasticd service..."
        if sudo systemctl start meshtasticd 2>&1; then
            sleep 3
            if check_service_status "meshtasticd"; then
                print_success "meshtasticd service started"
                log_message "Started meshtasticd service"
                if check_meshtasticd_http_api; then
                    print_success "HTTP API available at $MESHTASTICD_HTTP_URL"
                else
                    print_info "HTTP API not yet available (may need a few seconds)"
                fi
            else
                print_error "meshtasticd failed to start"
                echo -e "  ${CYAN}Check logs:${NC} sudo journalctl -u meshtasticd --no-pager -n 20"
            fi
        else
            print_error "Failed to start meshtasticd"
            echo -e "  ${CYAN}Check status:${NC} sudo systemctl status meshtasticd"
        fi
    fi
    invalidate_status_cache
}

# Stop meshtasticd service
meshtasticd_stop() {
    print_section "Stopping meshtasticd"
    if ! command -v meshtasticd &>/dev/null; then
        print_error "meshtasticd is not installed"
    elif ! check_service_status "meshtasticd"; then
        print_info "meshtasticd is not running"
    else
        print_info "Stopping meshtasticd service..."
        if sudo systemctl stop meshtasticd 2>&1; then
            sleep 2
            if ! check_service_status "meshtasticd"; then
                print_success "meshtasticd stopped"
                log_message "Stopped meshtasticd service"
            else
                print_warning "meshtasticd may still be stopping..."
            fi
        else
            print_error "Failed to stop meshtasticd"
        fi
    fi
    invalidate_status_cache
}

# Restart meshtasticd service
meshtasticd_restart() {
    print_section "Restarting meshtasticd"
    if ! command -v meshtasticd &>/dev/null; then
        print_error "meshtasticd is not installed"
    else
        print_info "Restarting meshtasticd service..."
        if sudo systemctl restart meshtasticd 2>&1; then
            sleep 3
            if check_service_status "meshtasticd"; then
                print_success "meshtasticd restarted"
                log_message "Restarted meshtasticd service"
                if check_meshtasticd_http_api; then
                    print_success "HTTP API available at $MESHTASTICD_HTTP_URL"
                else
                    print_info "HTTP API not yet available (may need a few seconds)"
                fi
            else
                print_error "meshtasticd failed to restart"
                echo -e "  ${CYAN}Check logs:${NC} sudo journalctl -u meshtasticd --no-pager -n 20"
            fi
        else
            print_error "Failed to restart meshtasticd"
        fi
    fi
    invalidate_status_cache
}

# Check meshtasticd HTTP API and configuration (ported from meshforge diagnostics)
meshtasticd_check_api() {
    print_section "meshtasticd HTTP API & Configuration"
    if ! command -v meshtasticd &>/dev/null; then
        print_error "meshtasticd is not installed"
        return
    fi

    # Version info
    local mtd_ver
    mtd_ver=$(meshtasticd --version 2>&1 | head -1 || echo "unknown")
    echo -e "  Version: ${BOLD}${mtd_ver}${NC}"
    echo ""

    # Service status
    echo -e "${BOLD}Service Status:${NC}"
    if check_service_status "meshtasticd"; then
        print_success "meshtasticd service is running"
    else
        print_warning "meshtasticd service is not running"
        echo -e "  ${YELLOW}Start with: sudo systemctl start meshtasticd${NC}"
    fi
    echo ""

    # Config validation
    echo -e "${BOLD}Configuration:${NC}"
    local config_hint
    config_hint=$(check_meshtasticd_webserver_config)
    local config_rc=$?
    if [ "$config_rc" -eq 0 ]; then
        print_success "$config_hint"
    else
        print_warning "$config_hint"
    fi
    echo ""

    # HTTP API probe
    echo -e "${BOLD}HTTP API Probe:${NC}"
    echo "  Testing ports 443, 9443, 80, 4403..."
    if check_meshtasticd_http_api; then
        print_success "HTTP API reachable at $MESHTASTICD_HTTP_URL"

        # Try to fetch node count from /json/nodes
        local nodes_response
        nodes_response=$(curl -sk --connect-timeout 3 --max-time 5 \
            "${MESHTASTICD_HTTP_URL}/json/nodes" 2>/dev/null)
        if [ -n "$nodes_response" ]; then
            local node_count
            node_count=$(echo "$nodes_response" | grep -o '"num"' | wc -l)
            if [ "$node_count" -gt 0 ]; then
                print_success "$node_count node(s) visible via HTTP API"
            fi
        fi
    else
        print_error "HTTP API not reachable on any port"
        echo ""
        echo -e "  ${BOLD}Troubleshooting:${NC}"
        echo "  1. Verify meshtasticd is running: sudo systemctl status meshtasticd"
        echo "  2. Check config has Webserver section: /etc/meshtasticd/config.yaml"
        echo "  3. Example config entry:"
        echo -e "     ${CYAN}Webserver:${NC}"
        echo -e "     ${CYAN}  Port: 443${NC}"
        echo -e "     ${CYAN}  RootPath: /usr/share/meshtasticd/web${NC}"
        echo "  4. Check logs: sudo journalctl -u meshtasticd --no-pager -n 30"
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

        show_services_status_box

        echo -e "${BOLD}Service Management:${NC}"
        echo ""
        echo -e "  ${CYAN}─── rnsd Daemon Control ───${NC}"
        echo "   1) Start rnsd daemon"
        echo "   2) Stop rnsd daemon"
        echo "   3) Restart rnsd daemon"
        echo "   4) View detailed status"
        echo ""
        if command -v meshtasticd &>/dev/null; then
            echo -e "  ${CYAN}─── meshtasticd Control ───${NC}"
            echo "  m1) Start meshtasticd"
            echo "  m2) Stop meshtasticd"
            echo "  m3) Restart meshtasticd"
            echo "  m4) Check HTTP API & config"
            echo ""
        fi
        echo -e "  ${CYAN}─── Network Tools ───${NC}"
        echo -e "   5) $(menu_item "View network statistics (rnstatus)" "$HAS_RNSTATUS")"
        echo -e "   6) $(menu_item "View path table (rnpath)" "$HAS_RNPATH")"
        echo -e "   7) $(menu_item "Probe destination (rnprobe)" "$HAS_RNPROBE")"
        echo -e "   8) $(menu_item "Transfer file (rncp)" "$HAS_RNCP")"
        echo -e "   9) $(menu_item "Remote command (rnx)" "$HAS_RNX")"
        echo ""
        echo -e "  ${CYAN}─── Identity & Boot ───${NC}"
        echo -e "  10) $(menu_item "Identity management (rnid)" "$HAS_RNID")"
        echo "  11) Enable auto-start on boot"
        echo "  12) Disable auto-start on boot"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r SVC_CHOICE

        case $SVC_CHOICE in
            1)  start_services; pause_for_input ;;
            2)  stop_services; pause_for_input ;;
            3)
                print_info "Restarting rnsd daemon..."
                stop_services
                start_services
                pause_for_input
                ;;
            4)  show_service_status; pause_for_input ;;
            5|6|7|8|9)
                handle_network_tools "$SVC_CHOICE"
                pause_for_input
                ;;
            10) handle_identity_management; pause_for_input ;;
            11) setup_autostart; pause_for_input ;;
            12) disable_autostart; pause_for_input ;;
            m1|M1) meshtasticd_start; pause_for_input ;;
            m2|M2) meshtasticd_stop; pause_for_input ;;
            m3|M3) meshtasticd_restart; pause_for_input ;;
            m4|M4) meshtasticd_check_api; pause_for_input ;;
            0|"") return ;;
            *)  print_error "Invalid option" ;;
        esac
    done
}

setup_autostart() {
    print_section "Setup Auto-Start"

    if [ ! -d "$REAL_HOME/.config/systemd/user" ]; then
        mkdir -p "$REAL_HOME/.config/systemd/user"
    fi

    local service_file="$REAL_HOME/.config/systemd/user/rnsd.service"

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
