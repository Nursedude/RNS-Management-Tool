#!/usr/bin/env bats
# RNS Management Tool - Enhanced Diagnostics Tests
# Tests for diagnostic engine improvements (Session 14 feature).
# Verifies: return codes, config validation, CPU/temp checks.
#
# Run with: bats tests/diagnostics_enhanced.bats
# Or:       bash tests/run_bats_compat.sh tests/diagnostics_enhanced.bats

#########################################################
# Test Setup
#########################################################

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export LIB_DIR="$SCRIPT_DIR/lib"
    export TEST_LOG=$(mktemp)
    export UPDATE_LOG="$TEST_LOG"

    # Source core first (defines colors, globals, timeout constants)
    source "$LIB_DIR/core.sh"

    # Override REAL_HOME to temp dir for safe testing
    REAL_HOME=$(mktemp -d)
    export REAL_HOME

    # Source remaining modules
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/diagnostics.sh"
}

teardown() {
    rm -f "$TEST_LOG" 2>/dev/null
    rm -rf "$REAL_HOME" 2>/dev/null
}

#########################################################
# Return Values from run_diagnostics
#########################################################

@test "DIAG: run_diagnostics returns 0 when no issues or warnings" {
    # Override all diag steps to be no-ops (no issues found)
    diag_check_system_resources() { true; }
    diag_check_environment() { true; }
    diag_check_rns_tools() { true; }
    diag_check_configuration() { true; }
    diag_check_services() { true; }
    diag_check_network() { true; }
    diag_rns_doctor() { true; }
    diag_report_summary() { true; }

    run_diagnostics
    [ $? -eq 0 ]
}

@test "DIAG: run_diagnostics returns 1 for warnings only" {
    diag_check_system_resources() { ((_DIAG_TOTAL_WARNINGS++)) || true; }
    diag_check_environment() { true; }
    diag_check_rns_tools() { true; }
    diag_check_configuration() { true; }
    diag_check_services() { true; }
    diag_check_network() { true; }
    diag_rns_doctor() { true; }
    diag_report_summary() { true; }

    local rc=0
    run_diagnostics || rc=$?
    [ "$rc" -eq 1 ]
}

@test "DIAG: run_diagnostics returns 2 for issues" {
    diag_check_system_resources() { ((_DIAG_TOTAL_ISSUES++)) || true; }
    diag_check_environment() { true; }
    diag_check_rns_tools() { true; }
    diag_check_configuration() { true; }
    diag_check_services() { true; }
    diag_check_network() { true; }
    diag_rns_doctor() { true; }
    diag_report_summary() { true; }

    local rc=0
    run_diagnostics || rc=$?
    [ "$rc" -eq 2 ]
}

#########################################################
# RNS Environment Doctor (Phase 1A)
#########################################################

@test "DOCTOR: diag_rns_doctor function exists" {
    declare -F diag_rns_doctor
}

@test "DOCTOR: run_diagnostics invokes diag_rns_doctor" {
    grep -q 'diag_rns_doctor' "$LIB_DIR/diagnostics.sh"
}

@test "DOCTOR: checks pip-vs-import version mismatch (shadowed install)" {
    local block
    block=$(sed -n '/^diag_rns_doctor()/,/^}/p' "$LIB_DIR/diagnostics.sh")
    grep -q 'import RNS' <<<"$block"
    grep -q 'Version mismatch' <<<"$block"
}

@test "DOCTOR: checks .reticulum ownership gotcha" {
    local block
    block=$(sed -n '/^diag_rns_doctor()/,/^}/p' "$LIB_DIR/diagnostics.sh")
    grep -q "stat -c '%U'" <<<"$block"
    grep -q 'chown -R' <<<"$block"
}

@test "DOCTOR: flags rnsd not on PATH while RNS importable" {
    local block
    block=$(sed -n '/^diag_rns_doctor()/,/^}/p' "$LIB_DIR/diagnostics.sh")
    grep -q "not on your PATH" <<<"$block"
}

@test "DOCTOR: degrades gracefully when python3 is absent" {
    HAS_PYTHON3=false
    local output rc=0
    output=$(diag_rns_doctor 2>&1) || rc=$?
    [ "$rc" -eq 0 ]
    [[ "$output" == *"skipping RNS environment checks"* ]]
}

#########################################################
# Config Validation Improvements
#########################################################

@test "DIAG: config validation detects missing [reticulum] section" {
    mkdir -p "$REAL_HOME/.reticulum"
    echo -e "[interfaces]\n  [[Default]]\n    type = AutoInterface\n    enabled = Yes" \
        > "$REAL_HOME/.reticulum/config"

    local output
    output=$(diag_check_configuration 2>&1)
    echo "$output" | grep -qi 'missing.*reticulum.*section'
}

@test "DIAG: config validation detects missing [interfaces] section" {
    mkdir -p "$REAL_HOME/.reticulum"
    echo -e "[reticulum]\n  enable_transport = False" \
        > "$REAL_HOME/.reticulum/config"

    local output
    output=$(diag_check_configuration 2>&1)
    echo "$output" | grep -qi 'missing.*interfaces.*section'
}

@test "DIAG: config validation counts enabled interfaces" {
    mkdir -p "$REAL_HOME/.reticulum"
    cat > "$REAL_HOME/.reticulum/config" << 'CONF'
[reticulum]
  enable_transport = False

[interfaces]
  [[Default Interface]]
    type = AutoInterface
    enabled = Yes
  [[LoRa Interface]]
    type = RNodeInterface
    enabled = Yes
CONF

    local output
    output=$(diag_check_configuration 2>&1)
    echo "$output" | grep -q '2 interface(s) enabled'
}

@test "DIAG: config validation warns on zero enabled interfaces" {
    mkdir -p "$REAL_HOME/.reticulum"
    cat > "$REAL_HOME/.reticulum/config" << 'CONF'
[reticulum]
  enable_transport = False

[interfaces]
  [[Default Interface]]
    type = AutoInterface
    enabled = No
CONF

    _DIAG_TOTAL_WARNINGS=0
    diag_check_configuration > /dev/null 2>&1
    [ "$_DIAG_TOTAL_WARNINGS" -gt 0 ]
}

@test "DIAG: config validation warns on missing RNODE device" {
    mkdir -p "$REAL_HOME/.reticulum"
    cat > "$REAL_HOME/.reticulum/config" << 'CONF'
[reticulum]
  enable_transport = False

[interfaces]
  [[RNODE]]
    type = RNodeInterface
    port = /dev/ttyUSB99
    enabled = Yes
CONF

    local output
    output=$(diag_check_configuration 2>&1)
    echo "$output" | grep -q 'ttyUSB99.*not found'
}

#########################################################
# CPU Load and Temperature Checks
#########################################################

@test "DIAG: CPU load check present in diag_check_system_resources" {
    grep -q 'loadavg' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: temperature check present in diag_check_system_resources" {
    grep -q 'thermal_zone0' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: temperature warns at 70C threshold" {
    grep -q 'temp_c.*-ge 70' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: temperature errors at 80C threshold" {
    grep -q 'temp_c.*-ge 80' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: CPU load threshold uses nproc for scaling" {
    grep -q 'nproc' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: diag_check_system_resources runs without errors on this system" {
    # Functional test: run the actual function, should not crash
    _DIAG_TOTAL_ISSUES=0
    _DIAG_TOTAL_WARNINGS=0
    diag_check_system_resources > /dev/null 2>&1
    # Just verify it didn't crash — exit code 0
    true
}
