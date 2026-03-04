# shellcheck shell=bash
#########################################################
# lib/diagnostics.sh — System diagnostics
# Sourced by rns_management_tool.sh
#########################################################

# Globals for accumulating diagnostic results across steps
_DIAG_TOTAL_ISSUES=0
_DIAG_TOTAL_WARNINGS=0

# Step 1: System resources — disk space and memory
# (adapted from meshforge improved diagnostics; reuses patterns from lib/install.sh)
diag_check_system_resources() {
    echo -e "${BLUE}▶ Step 1/7: System Resources${NC}"

    # Disk space check
    if command -v df &> /dev/null; then
        local avail_mb
        avail_mb=$(df -m "$REAL_HOME" 2>/dev/null | awk 'NR==2 {print $4}')
        if [ -n "$avail_mb" ]; then
            if [ "$avail_mb" -lt 100 ]; then
                print_error "Disk space critically low: ${avail_mb}MB available"
                ((_DIAG_TOTAL_ISSUES++))
            elif [ "$avail_mb" -lt 500 ]; then
                print_warning "Disk space low: ${avail_mb}MB available (recommend 500MB+)"
                ((_DIAG_TOTAL_WARNINGS++))
            else
                print_success "Disk space: ${avail_mb}MB available"
            fi
        fi
    fi

    # Memory check
    if [ -f /proc/meminfo ]; then
        local mem_total_kb mem_avail_kb
        mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
        mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
        if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ] && [ "$mem_total_kb" -gt 0 ]; then
            local mem_total_mb=$((mem_total_kb / 1024))
            local mem_avail_mb=$((mem_avail_kb / 1024))
            local mem_pct=$((mem_avail_kb * 100 / mem_total_kb))
            if [ "$mem_pct" -lt 10 ]; then
                print_warning "Memory low: ${mem_avail_mb}MB/${mem_total_mb}MB free (${mem_pct}%)"
                ((_DIAG_TOTAL_WARNINGS++))
            else
                print_success "Memory: ${mem_avail_mb}MB/${mem_total_mb}MB free (${mem_pct}%)"
            fi
        fi
    fi

    # CPU load check
    if [ -f /proc/loadavg ]; then
        local load_1m nproc_val
        load_1m=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
        nproc_val=$(nproc 2>/dev/null || echo 1)
        if [ -n "$load_1m" ] && [ -n "$nproc_val" ]; then
            local load_int nproc_thresh
            load_int=$(echo "$load_1m" | awk '{printf "%d", $1 * 100}')
            nproc_thresh=$((nproc_val * 200))
            if [ "$load_int" -gt "$nproc_thresh" ]; then
                print_warning "CPU load high: $load_1m (${nproc_val} cores)"
                ((_DIAG_TOTAL_WARNINGS++))
            else
                print_success "CPU load: $load_1m (${nproc_val} cores)"
            fi
        fi
    fi

    # Temperature check (Raspberry Pi / thermal_zone)
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        local temp_mc temp_c
        temp_mc=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [ -n "$temp_mc" ] && [ "$temp_mc" -gt 0 ] 2>/dev/null; then
            temp_c=$((temp_mc / 1000))
            if [ "$temp_c" -ge 80 ]; then
                print_error "CPU temperature critical: ${temp_c}°C (throttling likely)"
                ((_DIAG_TOTAL_ISSUES++))
            elif [ "$temp_c" -ge 70 ]; then
                print_warning "CPU temperature high: ${temp_c}°C"
                ((_DIAG_TOTAL_WARNINGS++))
            else
                print_success "CPU temperature: ${temp_c}°C"
            fi
        fi
    fi
    echo ""
}

# Step 2: Check environment and prerequisites
diag_check_environment() {
    echo -e "${BLUE}▶ Step 2/7: Environment & Prerequisites${NC}"

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
        ((_DIAG_TOTAL_ISSUES++))
    fi

    if [ "$HAS_PIP" = true ]; then
        print_success "pip available"
    else
        print_error "pip not found"
        echo -e "  ${YELLOW}Fix: sudo apt install python3-pip${NC}"
        ((_DIAG_TOTAL_ISSUES++))
    fi

    if [ "$PEP668_DETECTED" = true ]; then
        echo -e "  ${CYAN}[i] PEP 668: Python externally managed (Debian 12+)${NC}"
    fi
    echo ""
}

# Step 3: Check RNS tool availability
diag_check_rns_tools() {
    echo -e "${BLUE}▶ Step 3/7: RNS Tool Availability${NC}"

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
        ((_DIAG_TOTAL_WARNINGS++))
    fi
    echo ""
}

# Step 4: Validate Reticulum configuration
diag_check_configuration() {
    echo -e "${BLUE}▶ Step 4/7: Configuration Validation${NC}"

    local config_file="$REAL_HOME/.reticulum/config"
    if [ -f "$config_file" ]; then
        print_success "Config file exists: ~/.reticulum/config"

        local config_size
        config_size=$(wc -c < "$config_file" 2>/dev/null || echo 0)
        if [ "$config_size" -lt 10 ]; then
            print_error "Config file appears empty ($config_size bytes)"
            echo -e "  ${YELLOW}Fix: Apply a config template from Advanced > Apply Configuration Template${NC}"
            ((_DIAG_TOTAL_ISSUES++))
        fi

        if grep -q "interface_enabled = false" "$config_file" 2>/dev/null; then
            print_warning "Some interfaces are disabled in config"
            ((_DIAG_TOTAL_WARNINGS++))
        fi

        # Validate config structure — check required sections
        if ! grep -q '^\[reticulum\]' "$config_file" 2>/dev/null; then
            print_warning "Config missing [reticulum] section"
            ((_DIAG_TOTAL_WARNINGS++))
        fi

        if ! grep -q '^\[interfaces\]' "$config_file" 2>/dev/null; then
            print_warning "Config missing [interfaces] section"
            ((_DIAG_TOTAL_WARNINGS++))
        fi

        # Count enabled interfaces
        local enabled_ifaces
        enabled_ifaces=$(grep -cE '^\s+enabled\s*=\s*(True|Yes|true|yes)' "$config_file" 2>/dev/null || echo 0)
        if [ "$enabled_ifaces" -eq 0 ]; then
            print_warning "No enabled interfaces found in config"
            echo -e "  ${YELLOW}Fix: Enable at least one interface in ~/.reticulum/config${NC}"
            ((_DIAG_TOTAL_WARNINGS++))
        else
            print_success "$enabled_ifaces interface(s) enabled in config"
        fi

        # Check for RNODE port references to missing devices
        if grep -qE 'port\s*=\s*/dev/tty' "$config_file" 2>/dev/null; then
            local rnode_port
            rnode_port=$(grep -E 'port\s*=\s*/dev/tty' "$config_file" 2>/dev/null | head -1 | awk -F'=' '{print $2}' | tr -d '[:space:]')
            if [ -n "$rnode_port" ] && [ ! -e "$rnode_port" ]; then
                print_warning "Config references $rnode_port but device not found"
                echo -e "  ${YELLOW}Check RNODE connection or update port in config${NC}"
                ((_DIAG_TOTAL_WARNINGS++))
            fi
        fi

        if [ -d "$REAL_HOME/.reticulum/storage/identities" ]; then
            local id_count
            id_count=$(find "$REAL_HOME/.reticulum/storage/identities" -type f 2>/dev/null | wc -l)
            echo "  Known identities: $id_count"
        fi
    else
        print_warning "No configuration found"
        echo -e "  ${YELLOW}Fix: Run first-time setup or start rnsd to create default config${NC}"
        ((_DIAG_TOTAL_WARNINGS++))
    fi
    echo ""
}

# Step 5: Check service health (rnsd + meshtasticd)
diag_check_services() {
    echo -e "${BLUE}▶ Step 5/7: Service Health${NC}"

    # rnsd status with detection method tracking (meshforge ServiceStatus pattern)
    local rnsd_detection_method="none"
    local rnsd_running=false

    if command -v systemctl &>/dev/null && systemctl --user is-active rnsd.service &>/dev/null 2>&1; then
        rnsd_detection_method="systemctl"
        rnsd_running=true
    elif pgrep -x "rnsd" > /dev/null 2>&1; then
        rnsd_detection_method="pgrep"
        rnsd_running=true
    fi

    # Liveness verification via port check (reuses zombie detection logic)
    local port_bound=false
    if command -v ss &>/dev/null; then
        ss -ulnp 2>/dev/null | grep -q ':37428 ' && port_bound=true
    elif command -v netstat &>/dev/null; then
        netstat -ulnp 2>/dev/null | grep -q ':37428 ' && port_bound=true
    fi

    if [ "$rnsd_running" = true ]; then
        if [ "$port_bound" = true ]; then
            print_success "rnsd daemon is running (via $rnsd_detection_method, port 37428 bound)"
        else
            print_warning "rnsd process detected (via $rnsd_detection_method) but port 37428 not bound"
            echo -e "  ${YELLOW}This may indicate a zombie process — try restarting rnsd${NC}"
            ((_DIAG_TOTAL_WARNINGS++))
        fi

        # Uptime display
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
        ((_DIAG_TOTAL_WARNINGS++))
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
                ((_DIAG_TOTAL_WARNINGS++))
            fi
        else
            print_warning "meshtasticd installed but not running"
            echo -e "  ${YELLOW}Fix: sudo systemctl start meshtasticd${NC}"
            ((_DIAG_TOTAL_WARNINGS++))
        fi
    fi
    echo ""
}

# Step 6: Check network interfaces and USB devices
diag_check_network() {
    echo -e "${BLUE}▶ Step 6/7: Network & Interfaces${NC}"

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
            ((_DIAG_TOTAL_WARNINGS++))
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
            ((_DIAG_TOTAL_WARNINGS++))
        fi
    else
        echo -e "  ${CYAN}[i] No USB serial devices (RNODE) detected${NC}"
    fi

    # SPI device detection for RNODE HAT configurations (meshforge hardware detection)
    echo ""
    local spi_available=false
    if ls /dev/spidev* &>/dev/null 2>&1; then
        spi_available=true
        local spi_count
        spi_count=$(ls /dev/spidev* 2>/dev/null | wc -l)
        print_success "$spi_count SPI device(s) detected"
        ls /dev/spidev* 2>/dev/null | while read -r dev; do
            echo "  $dev"
        done
    fi

    if [ "$IS_RASPBERRY_PI" = true ]; then
        local boot_config=""
        for cfg in /boot/config.txt /boot/firmware/config.txt; do
            [ -r "$cfg" ] && boot_config="$cfg" && break
        done

        if [ -n "$boot_config" ]; then
            if grep -q 'dtparam=spi=on' "$boot_config" 2>/dev/null; then
                [ "$spi_available" = false ] && print_info "SPI enabled in $boot_config but no /dev/spidev* found"
            else
                echo -e "  ${CYAN}[i] SPI not enabled in $boot_config${NC}"
                echo -e "  ${CYAN}    Enable with: sudo raspi-config > Interface Options > SPI${NC}"
            fi

            # Check for RNODE-relevant dtoverlays
            if grep -qE 'dtoverlay.*(spi|sx127|rfm|lora)' "$boot_config" 2>/dev/null; then
                print_success "LoRa-related dtoverlay found in $boot_config"
            fi
        fi
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
}

# Step 7: Print summary and recommendations
diag_report_summary() {
    echo -e "${BLUE}▶ Step 7/7: Summary & Recommendations${NC}"
    echo ""

    if [ "$_DIAG_TOTAL_ISSUES" -eq 0 ] && [ "$_DIAG_TOTAL_WARNINGS" -eq 0 ]; then
        print_success "All checks passed - system looks healthy"
    else
        [ "$_DIAG_TOTAL_ISSUES" -gt 0 ] && print_error "$_DIAG_TOTAL_ISSUES issue(s) found requiring attention"
        [ "$_DIAG_TOTAL_WARNINGS" -gt 0 ] && print_warning "$_DIAG_TOTAL_WARNINGS warning(s) found"
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
    log_message "Diagnostics complete: $_DIAG_TOTAL_ISSUES issues, $_DIAG_TOTAL_WARNINGS warnings"
}

#########################################################
# Diagnostics - Main Coordinator
#########################################################

run_diagnostics() {
    print_section "System Diagnostics"

    # Reset global counters — each step increments directly
    _DIAG_TOTAL_ISSUES=0
    _DIAG_TOTAL_WARNINGS=0

    echo -e "${BOLD}Running 7-step diagnostic...${NC}\n"

    diag_check_system_resources
    diag_check_environment
    diag_check_rns_tools
    diag_check_configuration
    diag_check_services
    diag_check_network
    diag_report_summary

    # Return value for scripted use:
    # 0 = all healthy, 1 = warnings only, 2 = issues found
    if [ "$_DIAG_TOTAL_ISSUES" -gt 0 ]; then
        return 2
    elif [ "$_DIAG_TOTAL_WARNINGS" -gt 0 ]; then
        return 1
    fi
    return 0
}
