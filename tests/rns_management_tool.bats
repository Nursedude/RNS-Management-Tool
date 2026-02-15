#!/usr/bin/env bats
# RNS Management Tool - Test Suite
# Requires: bats-core (https://github.com/bats-core/bats-core)
#
# Run with: bats tests/rns_management_tool.bats
# Or: ./tests/rns_management_tool.bats

# Test setup
setup() {
    # Source the script for testing functions
    # We only test pure functions, not interactive ones
    export SCRIPT_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )/.." && pwd )"
    export TEST_LOG="/tmp/rns_test_$$.log"
    export UPDATE_LOG="$TEST_LOG"
}

teardown() {
    # Cleanup test artifacts
    rm -f "$TEST_LOG" 2>/dev/null
}

#########################################################
# Syntax and Security Tests
#########################################################

@test "Script has valid bash syntax" {
    bash -n "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Script does not use eval" {
    # RNS001: No eval usage for security (exclude comments)
    ! grep -v '^\s*#' "$SCRIPT_DIR/rns_management_tool.sh" | grep -q '\beval\b'
}

@test "Script does not use shell=True pattern" {
    # Check for common shell injection patterns
    ! grep -qE '\$\([^)]*\).*\|.*bash' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Device port validation regex is present" {
    # RNS002: Device port validation
    grep -q '/dev/tty\[A-Za-z0-9\]' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Spreading factor validation range is 7-12" {
    # RNS003: Numeric range validation
    grep -q 'SF.*-ge 7.*-le 12\|SF.*7.*12' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "TX power validation range is -10 to 30" {
    # RNS003: Numeric range validation
    grep -q 'TXP.*-10.*30\|-10.*TXP.*30' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Archive validation checks for path traversal" {
    # RNS004: Path traversal prevention
    grep -q '\.\.\/' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Destructive actions require confirmation" {
    # RNS005: Confirmation for destructive actions
    grep -q 'confirm_action\|yes/no\|Y/n' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Network timeout constants are defined" {
    # RNS006: Subprocess timeout protection
    grep -q 'NETWORK_TIMEOUT\|APT_TIMEOUT\|PIP_TIMEOUT' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Timeout wrapper function exists" {
    grep -q 'run_with_timeout' "$SCRIPT_DIR/rns_management_tool.sh"
}

#########################################################
# Function Existence Tests
#########################################################

@test "Print functions exist" {
    grep -q 'print_header\|print_section\|print_success\|print_error' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "RNODE helper functions exist" {
    grep -q 'rnode_autoinstall\|rnode_configure_radio\|rnode_get_device_port' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Backup functions exist" {
    grep -q 'create_backup\|import_configuration\|export_configuration' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Service management functions exist" {
    grep -q 'start_rnsd\|stop_services\|show_service_status' "$SCRIPT_DIR/rns_management_tool.sh"
}

#########################################################
# Version Tests
#########################################################

@test "Version is set to 0.3.4-beta" {
    grep -q 'SCRIPT_VERSION="0.3.4-beta"' "$SCRIPT_DIR/rns_management_tool.sh"
}

#########################################################
# UI Pattern Tests
#########################################################

@test "Menu uses box drawing characters" {
    grep -qE '╔|╚|║|─|┌|└|│' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Color codes are defined" {
    grep -q "RED='\|GREEN='\|YELLOW='\|CYAN='" "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Breadcrumb navigation exists" {
    grep -q 'print_breadcrumb\|MENU_BREADCRUMB' "$SCRIPT_DIR/rns_management_tool.sh"
}

#########################################################
# Environment Detection Tests (from meshforge patterns)
#########################################################

@test "Terminal capability detection exists" {
    grep -q 'detect_terminal_capabilities' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Color fallback for dumb terminals exists" {
    grep -q 'HAS_COLOR' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "SCRIPT_DIR is resolved" {
    grep -q 'SCRIPT_DIR=.*BASH_SOURCE' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Sudo-aware home resolution exists" {
    grep -q 'resolve_real_home\|REAL_HOME' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "SSH session detection exists" {
    grep -q 'IS_SSH\|SSH_CLIENT\|SSH_TTY' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "PEP 668 detection exists" {
    grep -q 'PEP668_DETECTED\|EXTERNALLY-MANAGED' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Disk space check function exists" {
    grep -q 'check_disk_space' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Memory check function exists" {
    grep -q 'check_available_memory' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Git safe.directory guard exists" {
    grep -q 'ensure_git_safe_directory' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Cleanup trap handler exists" {
    grep -q 'cleanup_on_exit\|trap.*EXIT' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Log levels are defined" {
    grep -q 'LOG_LEVEL_DEBUG\|LOG_LEVEL_INFO\|log_debug\|log_warn\|log_error' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Startup health check exists" {
    grep -q 'run_startup_health_check' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "SUDO_USER path traversal prevention exists" {
    # Meshforge security pattern: prevent path traversal in sudo user
    grep -q 'sudo_user.*\.\.' "$SCRIPT_DIR/rns_management_tool.sh"
}

#########################################################
# Session 4: New Feature Tests
#########################################################

@test "Centralized check_service_status function exists" {
    grep -q 'check_service_status()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "safe_call wrapper function exists" {
    grep -q 'safe_call()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Main menu uses safe_call for dispatching" {
    grep -q 'safe_call.*install_meshchat\|safe_call.*install_sideband' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "First-run wizard function exists" {
    grep -q 'first_run_wizard()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Config templates directory exists" {
    [ -d "$SCRIPT_DIR/config_templates" ]
}

@test "All four config templates exist" {
    [ -f "$SCRIPT_DIR/config_templates/minimal.conf" ] &&
    [ -f "$SCRIPT_DIR/config_templates/lora_rnode.conf" ] &&
    [ -f "$SCRIPT_DIR/config_templates/tcp_client.conf" ] &&
    [ -f "$SCRIPT_DIR/config_templates/transport_node.conf" ]
}

@test "Config templates are marked as reference files" {
    grep -q 'REFERENCE TEMPLATE' "$SCRIPT_DIR/config_templates/minimal.conf"
}

@test "apply_config_template function exists" {
    grep -q 'apply_config_template()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Config template apply creates backup before overwriting" {
    grep -q 'config.backup.*date' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "edit_config_file function exists" {
    grep -q 'edit_config_file()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Path table menu option exists" {
    grep -q 'rnpath -t' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Probe destination menu option exists" {
    grep -q 'rnprobe' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "No raw pgrep calls outside approved functions" {
    # pgrep should only appear inside: check_service_status(), get_cached_rnsd_status(), run_diagnostics(), and comments
    # Count non-comment pgrep lines
    local total_pgrep
    total_pgrep=$(grep -c 'pgrep' "$SCRIPT_DIR/rns_management_tool.sh")
    # Count comment lines mentioning pgrep
    local comment_pgrep
    comment_pgrep=$(grep 'pgrep' "$SCRIPT_DIR/rns_management_tool.sh" | grep -c '^\s*#\|# .*pgrep')
    # Approved pgrep sites: check_service_status body (8), get_cached_rnsd_status (1), run_diagnostics (1) = 10
    local approved=10
    local expected=$((comment_pgrep + approved))
    [ "$total_pgrep" -le "$expected" ]
}

#########################################################
# Session 5: Reliability Improvements
#########################################################

@test "detect_available_tools function exists" {
    grep -q 'detect_available_tools()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "detect_available_tools is called at startup" {
    grep -q 'detect_available_tools' "$SCRIPT_DIR/rns_management_tool.sh"
    # Verify it's called in main()
    grep -A5 'main()' "$SCRIPT_DIR/rns_management_tool.sh" | grep -q 'detect_available_tools'
}

@test "Tool availability flags are defined" {
    grep -q 'HAS_RNSD=false' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'HAS_RNSTATUS=false' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'HAS_RNPATH=false' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'HAS_RNPROBE=false' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'HAS_RNCP=false' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'HAS_RNX=false' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'HAS_RNID=false' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'HAS_RNODECONF=false' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "All 8 RNS tools are scanned in detect_available_tools" {
    # Verify detect_available_tools checks all 8 RNS utilities
    local script="$SCRIPT_DIR/rns_management_tool.sh"
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rnsd' &&
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rnstatus' &&
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rnpath' &&
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rnprobe' &&
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rncp' &&
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rnx' &&
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rnid' &&
    grep -A30 'detect_available_tools()' "$script" | grep -q 'command -v rnodeconf'
}

@test "invalidate_status_cache re-detects tools" {
    grep -A10 'invalidate_status_cache()' "$SCRIPT_DIR/rns_management_tool.sh" | grep -q 'detect_available_tools'
}

@test "menu_item helper function exists" {
    grep -q 'menu_item()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Tool count shown in main menu dashboard" {
    grep -q 'RNS tools:.*available' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "rncp file transfer menu option exists" {
    grep -q 'File Transfer (rncp)\|Transfer file (rncp)' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "rnx remote execution menu option exists" {
    grep -q 'Remote Command (rnx)\|Remote command (rnx)' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "rnid identity management menu option exists" {
    grep -q 'Identity Management (rnid)\|Identity management (rnid)' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "6-step diagnostics implemented" {
    grep -q 'Step 1/6' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'Step 2/6' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'Step 3/6' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'Step 4/6' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'Step 5/6' "$SCRIPT_DIR/rns_management_tool.sh" &&
    grep -q 'Step 6/6' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Diagnostics provides actionable remediation suggestions" {
    grep -q 'Fix:' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Diagnostics checks config file validity" {
    # Step 3 should validate config file exists and isn't empty
    grep -q 'config_size\|Config file appears empty' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Emergency quick mode function exists" {
    grep -q 'emergency_quick_mode()' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Quick mode accessible from main menu" {
    grep -q 'q) Quick Mode\|q|Q)' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Quick mode uses safe_call in main dispatch" {
    grep -q 'safe_call.*Quick Mode.*emergency_quick_mode\|safe_call "Quick Mode" emergency_quick_mode' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Services menu has structured sections" {
    # Verify the services menu uses section headers
    grep -q 'Daemon Control\|Network Tools\|Identity & Boot' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "Services menu uses capability flags" {
    # Verify services menu uses HAS_* flags instead of command -v
    grep -q 'HAS_RNSTATUS.*true\|HAS_RNPATH.*true\|HAS_RNPROBE.*true' "$SCRIPT_DIR/rns_management_tool.sh"
}

#########################################################
# Integration Tests (require external tools)
#########################################################

@test "shellcheck passes with no errors" {
    if command -v shellcheck &>/dev/null; then
        shellcheck -x "$SCRIPT_DIR/rns_management_tool.sh"
    else
        skip "shellcheck not installed"
    fi
}
