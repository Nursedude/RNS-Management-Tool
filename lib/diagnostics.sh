# shellcheck shell=bash
#########################################################
# lib/diagnostics.sh — System diagnostics with return-value pattern
# Sourced by rns_management_tool.sh
#########################################################

# Step 1: Check environment and prerequisites
# Returns issue/warning counts via stdout (last line: DIAG_RESULT:issues:warnings)
diag_check_environment() {
    local _diag_issues=0
    local _diag_warnings=0

    echo -e "${BLUE}▶ Step 1/6: Environment & Prerequisites${NC}"

    echo "  Platform: $OS_TYPE ($ARCHITECTURE)"
    [ "$IS_RASPBERRY_PI" = true ] && echo "  Raspberry Pi: $PI_MODEL"
    [ "$IS_WSL" = true ] && echo "  Running in WSL"
    [ "$IS_SSH" = true ] && echo "  Connected via SSH"

    if [ "$HAS_PYTHON3" = true ]; then
        local pyver
        pyver=$(python3 --version 2>&1)
        print_success "$pyver"
    else
        print_error "Python 3 not found"
        echo -e "  ${YELLOW}Fix: sudo apt install python3 python3-pip${NC}"
        ((_diag_issues++))
    fi

    if [ "$HAS_PIP" = true ]; then
        print_success "pip available"
    else
        print_error "pip not found"
        echo -e "  ${YELLOW}Fix: sudo apt install python3-pip${NC}"
        ((_diag_issues++))
    fi

    if [ "$PEP668_DETECTED" = true ]; then
        echo -e "  ${CYAN}[i] PEP 668: Python externally managed (Debian 12+)${NC}"
    fi
    echo ""

    echo "DIAG_RESULT:$_diag_issues:$_diag_warnings"
}

# Step 2: Check RNS tool availability
diag_check_rns_tools() {
    local _diag_issues=0
    local _diag_warnings=0

    echo -e "${BLUE}▶ Step 2/6: RNS Tool Availability${NC}"

    local tool_list=(
        "rnsd:$HAS_RNSD:daemon"
        "rnstatus:$HAS_RNSTATUS:network status"
        "rnpath:$HAS_RNPATH:path table"
        "rnprobe:$HAS_RNPROBE:connectivity probe"
        "rncp:$HAS_RNCP:file transfer"
        "rnx:$HAS_RNX:remote execution"
        "rnid:$HAS_RNID:identity management"
        "rnodeconf:$HAS_RNODECONF:RNODE configuration"
    )

    local tool_missing=0
    for entry in "${tool_list[@]}"; do
        local tname tstate tdesc
        tname="${entry%%:*}"
        local rest="${entry#*:}"
        tstate="${rest%%:*}"
        tdesc="${rest#*:}"
        if [ "$tstate" = "true" ]; then
            print_success "$tname ($tdesc)"
        else
            echo -e "  ${YELLOW}○${NC} $tname ($tdesc) - not installed"
            ((tool_missing++))
        fi
    done

    if [ "$tool_missing" -gt 0 ]; then
        echo ""
        echo -e "  ${CYAN}[i] Install missing tools: pip3 install rns${NC}"
        ((_diag_warnings++))
    fi
    echo ""

    echo "DIAG_RESULT:$_diag_issues:$_diag_warnings"
}

# Step 3: Validate Reticulum configuration
diag_check_configuration() {
    local _diag_issues=0
    local _diag_warnings=0

    echo -e "${BLUE}▶ Step 3/6: Configuration Validation${NC}"

    local config_file="$REAL_HOME/.reticulum/config"
    if [ -f "$config_file" ]; then
        print_success "Config file exists: ~/.reticulum/config"

        local config_size
        config_size=$(wc -c < "$config_file" 2>/dev/null || echo 0)
        if [ "$config_size" -lt 10 ]; then
            print_error "Config file appears empty ($config_size bytes)"
            echo -e "  ${YELLOW}Fix: Apply a config template from Advanced > Apply Configuration Template${NC}"
            ((_diag_issues++))
        fi

        if grep -q "interface_enabled = false" "$config_file" 2>/dev/null; then
            print_warning "Some interfaces are disabled in config"
            ((_diag_warnings++))
        fi

        if [ -d "$REAL_HOME/.reticulum/storage/identities" ]; then
            local id_count
            id_count=$(find "$REAL_HOME/.reticulum/storage/identities" -type f 2>/dev/null | wc -l)
            echo "  Known identities: $id_count"
        fi
    else
        print_warning "No configuration found"
        echo -e "  ${YELLOW}Fix: Run first-time setup or start rnsd to create default config${NC}"
        ((_diag_warnings++))
    fi
    echo ""

    echo "DIAG_RESULT:$_diag_issues:$_diag_warnings"
}

# Step 4: Check service health (rnsd + meshtasticd)
diag_check_services() {
    local _diag_issues=0
    local _diag_warnings=0

    echo -e "${BLUE}▶ Step 4/6: Service Health${NC}"

    if check_service_status "rnsd"; then
        print_success "rnsd daemon is running"

        local rnsd_pid
        rnsd_pid=$(pgrep -x "rnsd" 2>/dev/null | head -1)
        if [ -n "$rnsd_pid" ] && [ -d "/proc/$rnsd_pid" ]; then
            local start_time
            start_time=$(stat -c %Y "/proc/$rnsd_pid" 2>/dev/null)
            if [ -n "$start_time" ]; then
                local now_time uptime_secs
                now_time=$(date +%s)
                uptime_secs=$((now_time - start_time))
                if [ "$uptime_secs" -lt 60 ]; then
                    echo "  Uptime: ${uptime_secs}s"
                elif [ "$uptime_secs" -lt 3600 ]; then
                    echo "  Uptime: $((uptime_secs / 60))m"
                else
                    echo "  Uptime: $((uptime_secs / 3600))h $((uptime_secs % 3600 / 60))m"
                fi
            fi
        fi
    else
        print_warning "rnsd daemon is not running"
        echo -e "  ${YELLOW}Fix: Start from Services menu or run: rnsd --daemon${NC}"
        ((_diag_warnings++))
    fi

    if command -v systemctl &>/dev/null; then
        if systemctl --user is-enabled rnsd.service &>/dev/null 2>&1; then
            print_success "Auto-start enabled at boot"
        else
            echo -e "  ${CYAN}[i] Auto-start not enabled (enable from Services menu)${NC}"
        fi
    fi

    # meshtasticd health check (ported from meshforge dashboard_mixin.py)
    if command -v meshtasticd &>/dev/null; then
        echo ""
        echo -e "  ${CYAN}meshtasticd Integration:${NC}"

        if check_service_status "meshtasticd"; then
            print_success "meshtasticd service is running"

            if check_meshtasticd_http_api; then
                print_success "meshtasticd HTTP API reachable at $MESHTASTICD_HTTP_URL"
            else
                print_warning "meshtasticd HTTP API not reachable (tried ports 443, 9443, 80, 4403)"
                local config_hint
                config_hint=$(check_meshtasticd_webserver_config)
                echo -e "  ${YELLOW}${config_hint}${NC}"
                ((_diag_warnings++))
            fi
        else
            print_warning "meshtasticd installed but not running"
            echo -e "  ${YELLOW}Fix: sudo systemctl start meshtasticd${NC}"
            ((_diag_warnings++))
        fi
    fi
    echo ""

    echo "DIAG_RESULT:$_diag_issues:$_diag_warnings"
}

# Step 5: Check network interfaces and USB devices
diag_check_network() {
    local _diag_issues=0
    local _diag_warnings=0

    echo -e "${BLUE}▶ Step 5/6: Network & Interfaces${NC}"

    if command -v ip &> /dev/null; then
        local net_ifaces
        net_ifaces=$(ip -br addr 2>/dev/null | grep -v "^lo" | grep -c "UP" || echo 0)
        if [ "$net_ifaces" -gt 0 ]; then
            print_success "$net_ifaces network interface(s) up"
            ip -br addr 2>/dev/null | grep -v "^lo" | while read -r line; do
                echo "  $line"
            done
        else
            print_warning "No active network interfaces found"
            ((_diag_warnings++))
        fi
    fi

    # USB serial devices (RNODE)
    local usb_devices
    usb_devices=$(find /dev -maxdepth 1 \( -name 'ttyUSB*' -o -name 'ttyACM*' \) 2>/dev/null | wc -l)
    if [ "$usb_devices" -gt 0 ]; then
        print_success "$usb_devices USB serial device(s) detected"
        find /dev -maxdepth 1 \( -name 'ttyUSB*' -o -name 'ttyACM*' \) 2>/dev/null | while read -r dev; do
            echo "  $dev"
        done

        if ! groups 2>/dev/null | grep -q "dialout"; then
            print_warning "User not in dialout group"
            echo -e "  ${YELLOW}Fix: sudo usermod -aG dialout \$USER && logout${NC}"
            ((_diag_warnings++))
        fi
    else
        echo -e "  ${CYAN}[i] No USB serial devices (RNODE) detected${NC}"
    fi

    # RNS interface status (if rnstatus available and rnsd running)
    if [ "$HAS_RNSTATUS" = true ] && check_service_status "rnsd"; then
        echo ""
        echo -e "  ${CYAN}Reticulum Interface Status:${NC}"
        rnstatus 2>&1 | head -n 25 | while read -r line; do
            echo "  $line"
        done
    fi
    echo ""

    echo "DIAG_RESULT:$_diag_issues:$_diag_warnings"
}

# Step 6: Print summary and recommendations
# Takes total issues and warnings as parameters (return-value pattern)
diag_report_summary() {
    local diag_issues="${1:-0}"
    local diag_warnings="${2:-0}"

    echo -e "${BLUE}▶ Step 6/6: Summary & Recommendations${NC}"
    echo ""

    if [ "$diag_issues" -eq 0 ] && [ "$diag_warnings" -eq 0 ]; then
        print_success "All checks passed - system looks healthy"
    else
        [ "$diag_issues" -gt 0 ] && print_error "$diag_issues issue(s) found requiring attention"
        [ "$diag_warnings" -gt 0 ] && print_warning "$diag_warnings warning(s) found"
        echo ""
        echo -e "${BOLD}Recommended actions:${NC}"

        local config_file="$REAL_HOME/.reticulum/config"

        if [ "$HAS_RNSD" = false ]; then
            echo "  1. Install Reticulum: select option 1 from main menu"
        elif ! check_service_status "rnsd"; then
            echo "  1. Start rnsd: select option 7 > 1 from main menu"
        fi

        if [ ! -f "$config_file" ]; then
            echo "  2. Create configuration: use first-run wizard or Advanced > Templates"
        fi

        local usb_devices
        usb_devices=$(find /dev -maxdepth 1 \( -name 'ttyUSB*' -o -name 'ttyACM*' \) 2>/dev/null | wc -l)
        if [ "$usb_devices" -gt 0 ] && ! groups 2>/dev/null | grep -q "dialout"; then
            echo "  3. Add user to dialout group for RNODE access"
        fi
    fi

    echo ""
    log_message "Diagnostics complete: $diag_issues issues, $diag_warnings warnings"
}

#########################################################
# Diagnostics - Main Coordinator (return-value pattern)
#########################################################

# Helper: parse DIAG_RESULT line from step function output
# Displays all output except the result line, returns counts
_run_diag_step() {
    local output
    output=$("$@")

    # Print everything except the DIAG_RESULT line
    echo "$output" | grep -v "^DIAG_RESULT:"

    # Extract and return the result
    echo "$output" | grep "^DIAG_RESULT:" | tail -1
}

run_diagnostics() {
    print_section "System Diagnostics"

    local total_issues=0
    local total_warnings=0

    echo -e "${BOLD}Running 6-step diagnostic...${NC}\n"

    # Run each step and accumulate results
    local result_line

    result_line=$(_run_diag_step diag_check_environment)
    if [[ "$result_line" =~ DIAG_RESULT:([0-9]+):([0-9]+) ]]; then
        total_issues=$((total_issues + ${BASH_REMATCH[1]}))
        total_warnings=$((total_warnings + ${BASH_REMATCH[2]}))
    fi

    result_line=$(_run_diag_step diag_check_rns_tools)
    if [[ "$result_line" =~ DIAG_RESULT:([0-9]+):([0-9]+) ]]; then
        total_issues=$((total_issues + ${BASH_REMATCH[1]}))
        total_warnings=$((total_warnings + ${BASH_REMATCH[2]}))
    fi

    result_line=$(_run_diag_step diag_check_configuration)
    if [[ "$result_line" =~ DIAG_RESULT:([0-9]+):([0-9]+) ]]; then
        total_issues=$((total_issues + ${BASH_REMATCH[1]}))
        total_warnings=$((total_warnings + ${BASH_REMATCH[2]}))
    fi

    result_line=$(_run_diag_step diag_check_services)
    if [[ "$result_line" =~ DIAG_RESULT:([0-9]+):([0-9]+) ]]; then
        total_issues=$((total_issues + ${BASH_REMATCH[1]}))
        total_warnings=$((total_warnings + ${BASH_REMATCH[2]}))
    fi

    result_line=$(_run_diag_step diag_check_network)
    if [[ "$result_line" =~ DIAG_RESULT:([0-9]+):([0-9]+) ]]; then
        total_issues=$((total_issues + ${BASH_REMATCH[1]}))
        total_warnings=$((total_warnings + ${BASH_REMATCH[2]}))
    fi

    diag_report_summary "$total_issues" "$total_warnings"
}
