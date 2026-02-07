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
    # RNS001: No eval usage for security
    ! grep -q '\beval\b' "$SCRIPT_DIR/rns_management_tool.sh"
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

@test "Version is set to 0.3.0-beta" {
    grep -q 'SCRIPT_VERSION="0.3.0-beta"' "$SCRIPT_DIR/rns_management_tool.sh"
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
# Integration Tests (require external tools)
#########################################################

@test "shellcheck passes with no errors" {
    if command -v shellcheck &>/dev/null; then
        shellcheck -e SC2034,SC2086,SC1090 "$SCRIPT_DIR/rns_management_tool.sh"
    else
        skip "shellcheck not installed"
    fi
}
