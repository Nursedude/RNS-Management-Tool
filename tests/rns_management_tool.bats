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
    export MAIN_SCRIPT="$SCRIPT_DIR/rns_management_tool.sh"
    export LIB_DIR="$SCRIPT_DIR/lib"
    export TEST_LOG="/tmp/rns_test_$$.log"
    export UPDATE_LOG="$TEST_LOG"

    # Build combined source list: main script + all lib modules
    # Used for tests that search across the full codebase
    COMBINED_SOURCE="$MAIN_SCRIPT"
    if [ -d "$LIB_DIR" ]; then
        for module in "$LIB_DIR"/*.sh; do
            [ -f "$module" ] && COMBINED_SOURCE="$COMBINED_SOURCE $module"
        done
    fi
    export COMBINED_SOURCE
}

teardown() {
    # Cleanup test artifacts
    rm -f "$TEST_LOG" 2>/dev/null
}

#########################################################
# Syntax and Security Tests
#########################################################

@test "Script has valid bash syntax" {
    bash -n "$MAIN_SCRIPT"
}

@test "Script does not use eval" {
    # RNS001: No eval usage for security (exclude comments)
    ! grep -v '^\s*#' $COMBINED_SOURCE | grep -q '\beval\b'
}

@test "Script does not use shell=True pattern" {
    # Check for common shell injection patterns
    ! grep -qE '\$\([^)]*\).*\|.*bash' $COMBINED_SOURCE
}

@test "Device port validation regex is present" {
    # RNS002: Device port validation
    grep -q '/dev/tty\[A-Za-z0-9\]' $COMBINED_SOURCE
}

@test "Spreading factor validation range is 7-12" {
    # RNS003: Numeric range validation
    grep -q 'SF.*-ge 7.*-le 12\|SF.*7.*12' $COMBINED_SOURCE
}

@test "TX power validation range is -10 to 30" {
    # RNS003: Numeric range validation
    grep -q 'TXP.*-10.*30\|-10.*TXP.*30' $COMBINED_SOURCE
}

@test "Archive validation checks for path traversal" {
    # RNS004: Path traversal prevention
    grep -q '\.\.\/' $COMBINED_SOURCE
}

@test "Destructive actions require confirmation" {
    # RNS005: Confirmation for destructive actions
    grep -q 'confirm_action\|yes/no\|Y/n' $COMBINED_SOURCE
}

@test "Network timeout constants are defined" {
    # RNS006: Subprocess timeout protection
    grep -q 'NETWORK_TIMEOUT\|APT_TIMEOUT\|PIP_TIMEOUT' $COMBINED_SOURCE
}

@test "Timeout wrapper function exists" {
    grep -q 'run_with_timeout' $COMBINED_SOURCE
}

#########################################################
# Function Existence Tests
#########################################################

@test "Print functions exist" {
    grep -q 'print_header\|print_section\|print_success\|print_error' $COMBINED_SOURCE
}

@test "RNODE helper functions exist" {
    grep -q 'rnode_autoinstall\|rnode_configure_radio\|rnode_get_device_port' $COMBINED_SOURCE
}

@test "Backup functions exist" {
    grep -q 'create_backup\|import_configuration\|export_configuration' $COMBINED_SOURCE
}

@test "Service management functions exist" {
    grep -q 'start_services\|stop_services\|show_service_status' $COMBINED_SOURCE
}

#########################################################
# Version Tests
#########################################################

@test "Version is set to 0.3.4-beta" {
    grep -q 'SCRIPT_VERSION="0.3.4-beta"' $COMBINED_SOURCE
}

#########################################################
# UI Pattern Tests
#########################################################

@test "Menu uses box drawing characters" {
    grep -qE '╔|╚|║|─|┌|└|│' $COMBINED_SOURCE
}

@test "Color codes are defined" {
    grep -q "RED='\|GREEN='\|YELLOW='\|CYAN='" $COMBINED_SOURCE
}

@test "Breadcrumb navigation exists" {
    grep -q 'print_breadcrumb\|MENU_BREADCRUMB' $COMBINED_SOURCE
}

#########################################################
# Environment Detection Tests (from meshforge patterns)
#########################################################

@test "Terminal capability detection exists" {
    grep -q 'detect_terminal_capabilities' $COMBINED_SOURCE
}

@test "Color fallback for dumb terminals exists" {
    grep -q 'HAS_COLOR' $COMBINED_SOURCE
}

@test "SCRIPT_DIR is resolved" {
    grep -q 'SCRIPT_DIR=.*BASH_SOURCE' "$MAIN_SCRIPT"
}

@test "Sudo-aware home resolution exists" {
    grep -q 'resolve_real_home\|REAL_HOME' $COMBINED_SOURCE
}

@test "SSH session detection exists" {
    grep -q 'IS_SSH\|SSH_CLIENT\|SSH_TTY' $COMBINED_SOURCE
}

@test "PEP 668 detection exists" {
    grep -q 'PEP668_DETECTED\|EXTERNALLY-MANAGED' $COMBINED_SOURCE
}

@test "Disk space check function exists" {
    grep -q 'check_disk_space' $COMBINED_SOURCE
}

@test "Memory check function exists" {
    grep -q 'check_available_memory' $COMBINED_SOURCE
}

@test "Git safe.directory guard exists" {
    grep -q 'ensure_git_safe_directory' $COMBINED_SOURCE
}

@test "Cleanup trap handler exists" {
    grep -q 'cleanup_on_exit\|trap.*EXIT' $COMBINED_SOURCE
}

@test "Log levels are defined" {
    grep -q 'LOG_LEVEL_DEBUG\|LOG_LEVEL_INFO\|log_debug\|log_warn\|log_error' $COMBINED_SOURCE
}

@test "Startup health check exists" {
    grep -q 'run_startup_health_check' $COMBINED_SOURCE
}

@test "SUDO_USER path traversal prevention exists" {
    # Meshforge security pattern: prevent path traversal in sudo user
    grep -q 'sudo_user.*\.\.' $COMBINED_SOURCE
}

#########################################################
# Session 4: New Feature Tests
#########################################################

@test "Centralized check_service_status function exists" {
    grep -q 'check_service_status()' $COMBINED_SOURCE
}

@test "safe_call wrapper function exists" {
    grep -q 'safe_call()' $COMBINED_SOURCE
}

@test "Main menu uses safe_call for dispatching" {
    grep -q 'safe_call.*install_meshchat\|safe_call.*install_sideband' "$MAIN_SCRIPT"
}

@test "First-run wizard function exists" {
    grep -q 'first_run_wizard()' $COMBINED_SOURCE
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
    grep -q 'apply_config_template()' $COMBINED_SOURCE
}

@test "Config template apply creates backup before overwriting" {
    grep -q 'config.backup.*date' $COMBINED_SOURCE
}

@test "edit_config_file function exists" {
    grep -q 'edit_config_file()' $COMBINED_SOURCE
}

@test "Path table menu option exists" {
    grep -q 'rnpath -t' $COMBINED_SOURCE
}

@test "Probe destination menu option exists" {
    grep -q 'rnprobe' $COMBINED_SOURCE
}

@test "No raw pgrep calls outside approved functions" {
    # pgrep should only appear inside: check_service_status(), get_cached_rnsd_status(), run_diagnostics(), and comments
    # Count non-comment pgrep lines across all source files
    local total_pgrep
    total_pgrep=$(grep -c 'pgrep' $COMBINED_SOURCE | awk -F: '{s+=$NF} END {print s}')
    # Count comment lines mentioning pgrep
    local comment_pgrep
    comment_pgrep=$(grep 'pgrep' $COMBINED_SOURCE | grep -c '^\s*#\|# .*pgrep')
    # Approved pgrep sites: check_service_status body (8), get_cached_rnsd_status (1), run_diagnostics (1) = 10
    local approved=10
    local expected=$((comment_pgrep + approved))
    [ "$total_pgrep" -le "$expected" ]
}

#########################################################
# Session 5: Reliability Improvements
#########################################################

@test "detect_available_tools function exists" {
    grep -q 'detect_available_tools()' $COMBINED_SOURCE
}

@test "detect_available_tools is called at startup" {
    # Verify it's called in main()
    grep -A5 'main()' "$MAIN_SCRIPT" | grep -q 'detect_available_tools'
}

@test "Tool availability flags are defined" {
    grep -q 'HAS_RNSD=false' $COMBINED_SOURCE &&
    grep -q 'HAS_RNSTATUS=false' $COMBINED_SOURCE &&
    grep -q 'HAS_RNPATH=false' $COMBINED_SOURCE &&
    grep -q 'HAS_RNPROBE=false' $COMBINED_SOURCE &&
    grep -q 'HAS_RNCP=false' $COMBINED_SOURCE &&
    grep -q 'HAS_RNX=false' $COMBINED_SOURCE &&
    grep -q 'HAS_RNID=false' $COMBINED_SOURCE &&
    grep -q 'HAS_RNODECONF=false' $COMBINED_SOURCE
}

@test "All 8 RNS tools are scanned in detect_available_tools" {
    # Verify detect_available_tools checks all 8 RNS utilities
    # Function is now in lib/utils.sh
    local utils="$LIB_DIR/utils.sh"
    [ -f "$utils" ] || utils="$MAIN_SCRIPT"
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rnsd' &&
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rnstatus' &&
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rnpath' &&
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rnprobe' &&
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rncp' &&
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rnx' &&
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rnid' &&
    grep -A30 'detect_available_tools()' "$utils" | grep -q 'command -v rnodeconf'
}

@test "invalidate_status_cache re-detects tools" {
    # Function is now in lib/utils.sh
    local utils="$LIB_DIR/utils.sh"
    [ -f "$utils" ] || utils="$MAIN_SCRIPT"
    grep -A10 'invalidate_status_cache()' "$utils" | grep -q 'detect_available_tools'
}

@test "menu_item helper function exists" {
    grep -q 'menu_item()' $COMBINED_SOURCE
}

@test "Tool count shown in main menu dashboard" {
    grep -q 'RNS tools:.*available' $COMBINED_SOURCE
}

@test "rncp file transfer menu option exists" {
    grep -q 'File Transfer (rncp)\|Transfer file (rncp)' $COMBINED_SOURCE
}

@test "rnx remote execution menu option exists" {
    grep -q 'Remote Command (rnx)\|Remote command (rnx)' $COMBINED_SOURCE
}

@test "rnid identity management menu option exists" {
    grep -q 'Identity Management (rnid)\|Identity management (rnid)' $COMBINED_SOURCE
}

@test "6-step diagnostics implemented" {
    grep -q 'Step 1/6' $COMBINED_SOURCE &&
    grep -q 'Step 2/6' $COMBINED_SOURCE &&
    grep -q 'Step 3/6' $COMBINED_SOURCE &&
    grep -q 'Step 4/6' $COMBINED_SOURCE &&
    grep -q 'Step 5/6' $COMBINED_SOURCE &&
    grep -q 'Step 6/6' $COMBINED_SOURCE
}

@test "Diagnostics provides actionable remediation suggestions" {
    grep -q 'Fix:' $COMBINED_SOURCE
}

@test "Diagnostics checks config file validity" {
    # Step 3 should validate config file exists and isn't empty
    grep -q 'config_size\|Config file appears empty' $COMBINED_SOURCE
}

@test "Emergency quick mode function exists" {
    grep -q 'emergency_quick_mode()' $COMBINED_SOURCE
}

@test "Quick mode accessible from main menu" {
    grep -q 'q) Quick Mode\|q|Q)' "$MAIN_SCRIPT"
}

@test "Quick mode uses safe_call in main dispatch" {
    grep -q 'safe_call.*Quick Mode.*emergency_quick_mode\|safe_call "Quick Mode" emergency_quick_mode' "$MAIN_SCRIPT"
}

@test "Services menu has structured sections" {
    # Verify the services menu uses section headers
    grep -q 'Daemon Control\|Network Tools\|Identity & Boot' $COMBINED_SOURCE
}

@test "Services menu uses capability flags" {
    # Verify services menu uses HAS_* flags instead of command -v
    grep -q 'HAS_RNSTATUS.*true\|HAS_RNPATH.*true\|HAS_RNPROBE.*true' $COMBINED_SOURCE
}

#########################################################
# Integration Tests (require external tools)
#########################################################

@test "shellcheck passes with no errors" {
    if command -v shellcheck &>/dev/null; then
        shellcheck -x "$MAIN_SCRIPT"
    else
        skip "shellcheck not installed"
    fi
}
