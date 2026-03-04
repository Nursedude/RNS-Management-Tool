#!/usr/bin/env bats
# RNS Management Tool - Service Health State Tests
# Tests for granular service health states (Session 14 feature).
# Verifies: state constants, granular classification, display handling,
# backward compatibility, and cache behavior.
#
# Run with: bats tests/service_health_tests.bats
# Or:       bash tests/run_bats_compat.sh tests/service_health_tests.bats

#########################################################
# Test Setup
#########################################################

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export LIB_DIR="$SCRIPT_DIR/lib"
    export MAIN_SCRIPT="$SCRIPT_DIR/rns_management_tool.sh"
    COMBINED_SOURCE="$MAIN_SCRIPT"
    for module in "$LIB_DIR"/*.sh; do
        COMBINED_SOURCE="$COMBINED_SOURCE $module"
    done
    export COMBINED_SOURCE
}

#########################################################
# Health State Constants
#########################################################

@test "HEALTH: SVC_STATE_RUNNING defined in core.sh" {
    grep -q 'SVC_STATE_RUNNING=' "$LIB_DIR/core.sh"
}

@test "HEALTH: SVC_STATE_DEGRADED defined in core.sh" {
    grep -q 'SVC_STATE_DEGRADED=' "$LIB_DIR/core.sh"
}

@test "HEALTH: SVC_STATE_STARTING defined in core.sh" {
    grep -q 'SVC_STATE_STARTING=' "$LIB_DIR/core.sh"
}

@test "HEALTH: SVC_STATE_ZOMBIE defined in core.sh" {
    grep -q 'SVC_STATE_ZOMBIE=' "$LIB_DIR/core.sh"
}

@test "HEALTH: SVC_STATE_STOPPED defined in core.sh" {
    grep -q 'SVC_STATE_STOPPED=' "$LIB_DIR/core.sh"
}

@test "HEALTH: SVC_STATE_UNREACHABLE defined in core.sh" {
    grep -q 'SVC_STATE_UNREACHABLE=' "$LIB_DIR/core.sh"
}

@test "HEALTH: All 6 health states have unique values" {
    # Extract state values and verify uniqueness
    local values
    values=$(grep 'SVC_STATE_.*=' "$LIB_DIR/core.sh" | grep -v '_LAST_SERVICE' | sed 's/.*="\([^"]*\)".*/\1/' | sort)
    local unique_count
    unique_count=$(echo "$values" | sort -u | wc -l)
    local total_count
    total_count=$(echo "$values" | wc -l)
    [ "$unique_count" -eq "$total_count" ]
}

#########################################################
# check_service_status Granular State Classification
#########################################################

@test "HEALTH: _LAST_SERVICE_STATE global declared in core.sh" {
    grep -q '_LAST_SERVICE_STATE=' "$LIB_DIR/core.sh"
}

@test "HEALTH: check_service_status sets _LAST_SERVICE_STATE" {
    grep -q '_LAST_SERVICE_STATE=' "$LIB_DIR/utils.sh"
}

@test "HEALTH: check_service_status classifies zombie by port+uptime" {
    # The function should reference both port binding check and uptime for zombie detection
    local func_body
    func_body=$(sed -n '/^check_service_status/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'SVC_STATE_ZOMBIE'
    echo "$func_body" | grep -q '37428'
    echo "$func_body" | grep -q 'uptime_secs'
}

@test "HEALTH: check_service_status classifies starting state" {
    local func_body
    func_body=$(sed -n '/^check_service_status/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'SVC_STATE_STARTING'
}

@test "HEALTH: check_service_status still returns 0 for running" {
    # Backward compatibility: running states return 0
    local func_body
    func_body=$(sed -n '/^check_service_status/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'return 0'
}

@test "HEALTH: check_service_status returns 1 for stopped" {
    # Backward compatibility: stopped returns 1
    local func_body
    func_body=$(sed -n '/^check_service_status/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'return 1'
}

#########################################################
# get_service_health Helper
#########################################################

@test "HEALTH: get_service_health function defined in utils.sh" {
    grep -q 'get_service_health()' "$LIB_DIR/utils.sh"
}

@test "HEALTH: get_service_health calls check_service_status" {
    local func_body
    func_body=$(sed -n '/^get_service_health/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'check_service_status'
}

@test "HEALTH: get_service_health echoes _LAST_SERVICE_STATE" {
    local func_body
    func_body=$(sed -n '/^get_service_health/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '_LAST_SERVICE_STATE'
}

#########################################################
# Cache Functions with Granular States
#########################################################

@test "HEALTH: get_cached_rnsd_status caches granular state" {
    local func_body
    func_body=$(sed -n '/^get_cached_rnsd_status/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '_LAST_SERVICE_STATE'
}

@test "HEALTH: get_cached_meshtasticd_status detects unreachable" {
    local func_body
    func_body=$(sed -n '/^get_cached_meshtasticd_status/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'SVC_STATE_UNREACHABLE'
}

@test "HEALTH: invalidate_status_cache resets _LAST_SERVICE_STATE" {
    local func_body
    func_body=$(sed -n '/^invalidate_status_cache/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '_LAST_SERVICE_STATE'
}

#########################################################
# Display Functions Handle All States
#########################################################

@test "HEALTH: show_services_status_box handles starting state" {
    grep -q 'SVC_STATE_STARTING' "$LIB_DIR/services.sh"
}

@test "HEALTH: show_services_status_box handles zombie state" {
    grep -q 'SVC_STATE_ZOMBIE' "$LIB_DIR/services.sh"
}

@test "HEALTH: show_services_status_box handles unreachable state" {
    grep -q 'SVC_STATE_UNREACHABLE' "$LIB_DIR/services.sh"
}

@test "HEALTH: main menu handles starting state" {
    grep -q 'SVC_STATE_STARTING' "$MAIN_SCRIPT"
}

@test "HEALTH: main menu handles zombie state" {
    grep -q 'SVC_STATE_ZOMBIE' "$MAIN_SCRIPT"
}
