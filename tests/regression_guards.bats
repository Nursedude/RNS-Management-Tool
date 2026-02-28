#!/usr/bin/env bats
# Regression Guard Tests — Prevent reintroduction of fixed bugs
# These tests verify architectural invariants that MUST NOT regress.
# Adapted from meshforge test_regression_guards.py pattern.
#
# Run with: bats tests/regression_guards.bats

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export LIB_DIR="$SCRIPT_DIR/lib"
    export PWSH_DIR="$SCRIPT_DIR/pwsh"
}

#########################################################
# RNS001: No eval usage (command injection prevention)
#########################################################

@test "RNS001: no eval in main script" {
    # Exclude comments (with any leading whitespace) and grep/echo patterns
    ! grep -nE '(^|[^_a-zA-Z])eval ' "$SCRIPT_DIR/rns_management_tool.sh" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'grep' | grep -v 'echo.*eval' | grep -q .
}

@test "RNS001: no eval in any lib/ module" {
    local violations=0
    for f in "$LIB_DIR"/*.sh; do
        if grep -nE '(^|[^_a-zA-Z])eval ' "$f" 2>/dev/null | grep -v '^\s*#' | grep -q .; then
            echo "eval found in $(basename "$f")"
            ((violations++))
        fi
    done
    [ "$violations" -eq 0 ]
}

@test "RNS001: no backtick command substitution in lib/ (use \$() instead)" {
    local violations=0
    for f in "$LIB_DIR"/*.sh; do
        # Skip comments and grep patterns (backticks in regex are OK)
        if grep -nP '(?<!\\)`[^`]+`' "$f" 2>/dev/null | grep -v '^\s*#' | grep -v 'grep' | grep -v 'echo' | grep -q .; then
            echo "backtick substitution in $(basename "$f")"
            ((violations++))
        fi
    done
    [ "$violations" -eq 0 ]
}

#########################################################
# RNS002: Device port validation always present
#########################################################

@test "RNS002: rnode.sh uses validate_device_port (centralized)" {
    grep -q 'validate_device_port' "$LIB_DIR/rnode.sh"
}

@test "RNS002: validate_device_port defined in validation.sh" {
    grep -q 'validate_device_port()' "$LIB_DIR/validation.sh"
}

@test "RNS002: device port regex rejects path traversal" {
    # The regex ^/dev/tty[A-Za-z0-9]+$ must NOT match these:
    local bad_ports=("/dev/../etc/passwd" "/dev/tty;rm -rf /" "/dev/tty USB0" "ttyUSB0")
    for port in "${bad_ports[@]}"; do
        ! [[ "$port" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
    done
}

@test "RNS002: device port regex accepts valid ports" {
    local good_ports=("/dev/ttyUSB0" "/dev/ttyACM0" "/dev/ttyS0" "/dev/ttyAMA0")
    for port in "${good_ports[@]}"; do
        [[ "$port" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
    done
}

#########################################################
# RNS003: Numeric validation exists for radio params
#########################################################

@test "RNS003: validate_numeric_range defined in validation.sh" {
    grep -q 'validate_numeric_range()' "$LIB_DIR/validation.sh"
}

@test "RNS003: rnode.sh uses validate_numeric_range or validate_frequency" {
    grep -qE 'validate_numeric_range|validate_frequency' "$LIB_DIR/rnode.sh"
}

#########################################################
# RNS004: Archive path traversal prevention
#########################################################

@test "RNS004: validate_archive_contents defined in validation.sh" {
    grep -q 'validate_archive_contents()' "$LIB_DIR/validation.sh"
}

@test "RNS004: backup.sh calls validate_archive_contents or checks traversal" {
    grep -qE 'validate_archive_contents|\.\.\/' "$LIB_DIR/backup.sh"
}

@test "RNS004: symlink check present in archive validation" {
    grep -q 'symlink\|symlinks\|^l' "$LIB_DIR/validation.sh"
}

#########################################################
# RNS005: Destructive actions require confirmation
#########################################################

@test "RNS005: factory reset requires typing RESET" {
    grep -q 'RESET' "$LIB_DIR/advanced.sh"
}

@test "RNS005: factory reset creates safety backup" {
    # Factory reset is inline in advanced_menu, not a separate function.
    # Check that create_backup is called near the RESET confirmation.
    local context
    context=$(grep -A 15 'RESET.*confirm' "$LIB_DIR/advanced.sh")
    echo "$context" | grep -qE 'create_backup|backup'
}

@test "RNS005: bootloader update requires confirmation" {
    local func_body
    func_body=$(sed -n '/^rnode_bootloader()/,/^}/p' "$LIB_DIR/rnode.sh")
    echo "$func_body" | grep -q 'confirm_action'
}

#########################################################
# RNS006: Timeout protection
#########################################################

@test "RNS006: RNODECONF_TIMEOUT defined" {
    grep -q 'RNODECONF_TIMEOUT=' "$LIB_DIR/core.sh"
}

@test "RNS006: NETWORK_TIMEOUT defined" {
    grep -q 'NETWORK_TIMEOUT=' "$LIB_DIR/core.sh"
}

@test "RNS006: APT_TIMEOUT defined" {
    grep -q 'APT_TIMEOUT=' "$LIB_DIR/core.sh"
}

@test "RNS006: PIP_TIMEOUT defined" {
    grep -q 'PIP_TIMEOUT=' "$LIB_DIR/core.sh"
}

@test "RNS006: run_with_timeout has fallback" {
    local func_body
    func_body=$(sed -n '/^run_with_timeout()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '"$@"'
}

#########################################################
# Centralized service checks (no scattered pgrep -f)
#########################################################

@test "SERVICE: check_service_status is single source of truth" {
    grep -q 'check_service_status()' "$LIB_DIR/utils.sh"
}

@test "SERVICE: is_rnsd_running delegates to check_service_status" {
    local func_body
    func_body=$(sed -n '/^is_rnsd_running()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'check_service_status'
}

@test "SERVICE: no raw 'pgrep -f rnsd' outside check_service_status" {
    # pgrep -f for rnsd should only appear inside check_service_status
    # (pgrep -x is OK, pgrep -f with "rnsd" outside the function is not)
    local outside_func
    outside_func=$(sed '/^check_service_status()/,/^}/d' "$LIB_DIR/utils.sh")
    ! echo "$outside_func" | grep -q 'pgrep -f.*rnsd'
}

#########################################################
# Validation module integration
#########################################################

@test "VALIDATION: validation.sh sourced before utils.sh" {
    # In rns_management_tool.sh, validation.sh must come before utils.sh
    local val_line utils_line
    val_line=$(grep -n 'source.*validation.sh' "$SCRIPT_DIR/rns_management_tool.sh" | head -1 | cut -d: -f1)
    utils_line=$(grep -n 'source.*utils.sh' "$SCRIPT_DIR/rns_management_tool.sh" | head -1 | cut -d: -f1)
    [ -n "$val_line" ] && [ -n "$utils_line" ] && [ "$val_line" -lt "$utils_line" ]
}

@test "VALIDATION: validate_rns_hash not duplicated in utils.sh" {
    # Should be defined only in validation.sh, not in utils.sh
    ! grep -q '^validate_rns_hash()' "$LIB_DIR/utils.sh"
}

@test "VALIDATION: validate_rns_hash defined in validation.sh" {
    grep -q 'validate_rns_hash()' "$LIB_DIR/validation.sh"
}

#########################################################
# Security: No hardcoded secrets
#########################################################

@test "SECURITY: no hardcoded passwords in lib/" {
    ! grep -rnE 'password\s*=\s*["\x27][^"\x27]+["\x27]' "$LIB_DIR"/*.sh | grep -v '^\s*#' | grep -q .
}

@test "SECURITY: no hardcoded API keys in lib/" {
    ! grep -rnE 'api_key\s*=\s*["\x27][^"\x27]+["\x27]' "$LIB_DIR"/*.sh | grep -v '^\s*#' | grep -q .
}

#########################################################
# CI infrastructure
#########################################################

@test "CI: all CI jobs have timeout-minutes" {
    local job_count timeout_count
    job_count=$(grep -c 'runs-on:' "$SCRIPT_DIR/.github/workflows/lint.yml")
    timeout_count=$(grep -c 'timeout-minutes:' "$SCRIPT_DIR/.github/workflows/lint.yml")
    [ "$job_count" -eq "$timeout_count" ]
}

@test "CI: regression_guards.bats included in CI" {
    grep -q 'regression_guards.bats' "$SCRIPT_DIR/.github/workflows/lint.yml"
}

#########################################################
# MeshForge improvements (session 15)
#########################################################

# Phase 1: Scrollback clear + retry jitter

@test "UI: clear_screen clears scrollback buffer (033[3J)" {
    grep -q '\\033\[3J' "$LIB_DIR/ui.sh"
}

@test "RETRY: retry_with_backoff includes jitter" {
    local func_body
    func_body=$(sed -n '/^retry_with_backoff()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'jitter\|RANDOM'
}

# Phase 2: Zombie detection, enhanced safe_call, service pre-flight

@test "SERVICE: check_service_status rnsd case checks UDP port 37428" {
    local func_body
    func_body=$(sed -n '/^check_service_status()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '37428'
}

@test "SERVICE: zombie detection has ss fallback to netstat" {
    local func_body
    func_body=$(sed -n '/^check_service_status()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'netstat'
}

@test "SAFE_CALL: safe_call captures stderr to temp file" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'stderr_file'
}

@test "SAFE_CALL: safe_call matches known error patterns for hints" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'ImportError\|Permission denied\|Connection refused'
}

@test "SAFE_CALL: safe_call cleans up temp file on success" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'rm -f.*stderr_file'
}

@test "PREFLIGHT: require_service defined in utils.sh" {
    grep -q 'require_service()' "$LIB_DIR/utils.sh"
}

@test "PREFLIGHT: advise_service defined in utils.sh" {
    grep -q 'advise_service()' "$LIB_DIR/utils.sh"
}

@test "PREFLIGHT: handle_network_tools calls require_service" {
    grep -q 'require_service' "$LIB_DIR/services.sh"
}

@test "PREFLIGHT: edit_config_file calls advise_service" {
    grep -q 'advise_service' "$LIB_DIR/config.sh"
}

# Phase 3: Enhanced status line, diagnostics

@test "STATUS: get_status_line includes mtd indicator" {
    grep -q 'mtd:' "$LIB_DIR/ui.sh"
}

@test "STATUS: get_status_line includes USB device indicator" {
    grep -q 'USB:' "$LIB_DIR/ui.sh"
}

@test "DIAG: diag_check_services shows detection method" {
    grep -qE 'detection_method|via.*systemctl|via.*pgrep' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: diag_check_services checks port 37428" {
    grep -q '37428' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: diag_check_services warns on zombie process" {
    grep -q 'zombie' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: diag_check_network checks for SPI devices" {
    grep -q 'spidev' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: diag_check_network checks boot config for SPI on Pi" {
    grep -q 'dtparam=spi' "$LIB_DIR/diagnostics.sh"
}

# Phase 4: Startup conflict detection, quick mode pre-checks

@test "STARTUP: run_startup_health_check checks port 37428" {
    grep -q '37428' "$LIB_DIR/advanced.sh"
}

@test "STARTUP: port conflict detection uses ss with netstat fallback" {
    local func_body
    func_body=$(sed -n '/^run_startup_health_check()/,/^}/p' "$LIB_DIR/advanced.sh")
    echo "$func_body" | grep -q 'netstat'
}

@test "QUICKMODE: emergency_quick_mode checks rnsd before network tools" {
    local func_body
    func_body=$(sed -n '/^emergency_quick_mode()/,/^}/p' "$LIB_DIR/advanced.sh")
    echo "$func_body" | grep -q 'check_service_status.*rnsd'
}
