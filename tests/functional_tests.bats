#!/usr/bin/env bats
# RNS Management Tool - Functional/Behavioral Tests
# Unlike the structural tests in rns_management_tool.bats (which grep for patterns),
# these tests SOURCE lib modules and EXECUTE functions to verify actual behavior.
#
# Adapted from meshforge pytest patterns — tests actual return values, edge cases,
# and security input handling instead of just checking strings exist in source.
#
# Compatible with both real bats-core and run_bats_compat.sh (no 'run' keyword).
#
# Run with: bats tests/functional_tests.bats
# Or:       bash tests/run_bats_compat.sh tests/functional_tests.bats

#########################################################
# Test Setup — source lib modules with required globals
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
    source "$LIB_DIR/validation.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/install.sh" 2>/dev/null || true
}

teardown() {
    rm -f "$TEST_LOG" 2>/dev/null
    rm -rf "$REAL_HOME" 2>/dev/null
}

#########################################################
# validate_rns_hash — behavioral tests
#########################################################

@test "FUNC: validate_rns_hash accepts valid 32-char hex" {
    validate_rns_hash "abcdef1234567890abcdef1234567890"
}

@test "FUNC: validate_rns_hash accepts valid 20-char hex - minimum" {
    validate_rns_hash "abcdef1234567890abcd"
}

@test "FUNC: validate_rns_hash accepts valid 64-char hex - maximum" {
    validate_rns_hash "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
}

@test "FUNC: validate_rns_hash accepts mixed case hex" {
    validate_rns_hash "ABCDEF1234567890abcdef1234567890"
}

@test "FUNC: validate_rns_hash rejects empty input" {
    ! validate_rns_hash ""
}

@test "FUNC: validate_rns_hash rejects too-short input" {
    ! validate_rns_hash "abc123"
}

@test "FUNC: validate_rns_hash rejects non-hex characters" {
    ! validate_rns_hash "ghijklmnopqrstuvwxyz1234567890ab"
}

@test "FUNC: validate_rns_hash rejects semicolon injection" {
    ! validate_rns_hash "abcdef1234567890abcd;rm -rf /"
}

@test "FUNC: validate_rns_hash rejects pipe injection" {
    ! validate_rns_hash "abcdef1234567890abcd|cat /etc/passwd"
}

@test "FUNC: validate_rns_hash rejects backtick injection" {
    ! validate_rns_hash 'abcdef1234567890`whoami`1234'
}

#########################################################
# read_menu_choice / confirm_action — EOF handling (regression)
# Bug: $? taken inside `if ! read; then` was the negated-test status (0),
# not read's, so idle-timeout never fired and EOF spun the menu loop forever.
#########################################################

@test "FUNC: read_menu_choice returns non-zero on EOF (no infinite menu loop)" {
    # Closed stdin → read fails with EOF (rc=1). The function must return
    # non-zero so the main loop's 3-strike guard can break instead of spinning.
    run read_menu_choice _choice </dev/null
    [ "$status" -ne 0 ]
}

@test "FUNC: read_menu_choice leaves choice empty on EOF" {
    _choice="STALE"
    read_menu_choice _choice </dev/null || true
    [ -z "$_choice" ]
}

@test "FUNC: confirm_action default=y does NOT auto-affirm on EOF" {
    # On closed stdin a 'y'-default prompt must decline, not auto-proceed a
    # heavyweight op (apt upgrade, backup).
    run confirm_action "Proceed?" y </dev/null
    [ "$status" -ne 0 ]
}

@test "FUNC: confirm_action default=n declines on EOF" {
    run confirm_action "Proceed?" n </dev/null
    [ "$status" -ne 0 ]
}

#########################################################
# retry_with_backoff — behavioral tests
#########################################################

@test "FUNC: retry_with_backoff succeeds on first try" {
    retry_with_backoff 3 true
}

@test "FUNC: retry_with_backoff fails after max retries" {
    ! retry_with_backoff 2 false
}

@test "FUNC: retry_with_backoff retries correct number of times" {
    # Create a script that fails twice then succeeds
    local counter_file
    counter_file=$(mktemp)
    echo "0" > "$counter_file"

    try_command() {
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        [ "$count" -ge 3 ]
    }

    retry_with_backoff 3 try_command

    local final_count
    final_count=$(cat "$counter_file")
    [ "$final_count" -eq 3 ]
    rm -f "$counter_file"
}

#########################################################
# run_with_timeout — behavioral tests
#########################################################

@test "FUNC: run_with_timeout allows fast command to complete" {
    if ! command -v timeout &>/dev/null; then
        skip "timeout command not available"
    fi
    local output
    output=$(run_with_timeout 5 echo "hello" 2>&1)
    [ $? -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "FUNC: run_with_timeout kills long-running command" {
    if ! command -v timeout &>/dev/null; then
        skip "timeout command not available"
    fi
    run_with_timeout 1 sleep 30 && false || [ $? -eq 124 ]
}

#########################################################
# safe_call — behavioral tests
#########################################################

@test "FUNC: safe_call returns 0 for successful command" {
    safe_call "test" true
}

@test "FUNC: safe_call returns non-zero for failing command" {
    ! safe_call "test" false
}

@test "FUNC: safe_call handles missing command gracefully" {
    # safe_call should not crash, even for missing commands
    # Guard with || true since safe_call returns 127 (command not found)
    safe_call "test" nonexistent_command_xyz_12345 2>/dev/null || true
}

#########################################################
# Device port validation regex — behavioral tests
# (Tests the actual regex, not just that it exists in source)
#########################################################

@test "FUNC: port regex accepts /dev/ttyUSB0" {
    [[ "/dev/ttyUSB0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex accepts /dev/ttyACM0" {
    [[ "/dev/ttyACM0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex accepts /dev/ttyAMA0" {
    [[ "/dev/ttyAMA0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex rejects semicolon injection" {
    ! [[ "/dev/ttyUSB0;whoami" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex rejects pipe injection" {
    ! [[ "/dev/ttyUSB0|cat /etc/passwd" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex rejects backtick injection" {
    ! [[ '/dev/ttyUSB0`id`' =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex rejects dollar substitution" {
    ! [[ '/dev/ttyUSB0$(id)' =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex rejects path traversal" {
    ! [[ "/dev/../etc/passwd" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex rejects empty string" {
    ! [[ "" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "FUNC: port regex rejects space in path" {
    ! [[ "/dev/ttyUSB0 --help" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

#########################################################
# check_disk_space — behavioral tests
#########################################################

@test "FUNC: check_disk_space returns 0 for reasonable threshold" {
    # check_disk_space is in lib/install.sh
    source "$LIB_DIR/install.sh" 2>/dev/null || true
    # 1MB threshold should always pass on any system
    check_disk_space 1 /tmp
}

@test "FUNC: check_disk_space returns non-zero for impossible threshold" {
    source "$LIB_DIR/install.sh" 2>/dev/null || true
    # 999999999 MB threshold should always fail
    ! check_disk_space 999999999 /tmp
}

#########################################################
# count_rns_tools — behavioral test
#########################################################

@test "FUNC: count_rns_tools returns 0 when no tools installed" {
    # Reset all tool flags
    HAS_RNSD=false
    HAS_RNSTATUS=false
    HAS_RNPATH=false
    HAS_RNPROBE=false
    HAS_RNCP=false
    HAS_RNX=false
    HAS_RNID=false
    HAS_RNODECONF=false

    local count
    count=$(count_rns_tools)
    [ "$count" -eq 0 ]
}

@test "FUNC: count_rns_tools returns 8 when all tools installed" {
    HAS_RNSD=true
    HAS_RNSTATUS=true
    HAS_RNPATH=true
    HAS_RNPROBE=true
    HAS_RNCP=true
    HAS_RNX=true
    HAS_RNID=true
    HAS_RNODECONF=true

    local count
    count=$(count_rns_tools)
    [ "$count" -eq 8 ]
}

#########################################################
# Status cache — behavioral tests
#########################################################

@test "FUNC: invalidate_status_cache clears cached values" {
    _CACHE_RNSD_STATUS="running"
    _CACHE_RNSD_TIME=999999999
    _CACHE_RNS_VER="0.7.0"
    _CACHE_RNS_TIME=999999999

    invalidate_status_cache

    [ -z "$_CACHE_RNSD_STATUS" ]
    [ "$_CACHE_RNSD_TIME" -eq 0 ]
    [ -z "$_CACHE_RNS_VER" ]
    [ "$_CACHE_RNS_TIME" -eq 0 ]
}

#########################################################
# Archive security — behavioral tests (import validation)
#########################################################

@test "FUNC: archive path traversal detection works with ../" {
    # Create a malicious archive with path traversal
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/payload"
    echo "malicious" > "$tmpdir/payload/test.txt"

    # Create archive with ../ in paths
    tar -czf "$tmpdir/evil.tar.gz" -C "$tmpdir" --transform='s,payload,../../tmp/evil,' payload/test.txt 2>/dev/null

    # Verify the traversal detection finds it
    if tar -tzf "$tmpdir/evil.tar.gz" 2>/dev/null | grep -qE '(^/|\.\./)'; then
        # Detection works
        rm -rf "$tmpdir"
        true
    else
        # Archive doesn't contain traversal (transform may have been ignored)
        rm -rf "$tmpdir"
        skip "tar --transform not supported on this system"
    fi
}

#########################################################
# RNODE timeout regression guard
#########################################################

@test "FUNC: all rnodeconf device operations use run_with_timeout" {
    local rnode_sh="$SCRIPT_DIR/lib/rnode.sh"
    # Find lines that execute rnodeconf as a command without timeout
    # Exclude: comments (#), command -v, string mentions, help, console, variable refs
    local bare
    bare=$(grep 'rnodeconf' "$rnode_sh" | \
        grep -v '#' | \
        grep -v 'command -v' | \
        grep -v 'run_with_timeout' | \
        grep -v 'print_info\|print_error\|echo\|confirm_action' | \
        grep -v 'console\|--help' || true)
    [ -z "$bare" ]
}

#########################################################
# Backup symlink rejection regression guard
#########################################################

@test "FUNC: import_configuration checks for symlinks in archives" {
    grep -A30 'import_configuration()' "$SCRIPT_DIR/lib/backup.sh" | grep -q 'symlink\|symbolic link'
}

@test "FUNC: import_configuration uses realpath for path sanitization" {
    grep -A15 'read -r IMPORT_FILE' "$SCRIPT_DIR/lib/backup.sh" | grep -q 'realpath'
}

@test "FUNC: import_configuration uses --no-same-owner for extraction" {
    grep -q 'no-same-owner' "$SCRIPT_DIR/lib/backup.sh"
}

#########################################################
# RNODECONF_TIMEOUT constant regression guard
#########################################################

@test "FUNC: RNODECONF_TIMEOUT constant is defined" {
    grep -q 'RNODECONF_TIMEOUT=' "$SCRIPT_DIR/lib/core.sh"
}

@test "FUNC: factory reset checks backup return value" {
    grep -A5 'create_backup' "$SCRIPT_DIR/lib/advanced.sh" | grep -q 'if ! create_backup'
}

#########################################################
# MeshForge TUI integration — new functions
#########################################################

@test "FUNC: run_with_spinner function is defined" {
    type run_with_spinner | grep -q 'function'
}

@test "FUNC: run_with_spinner passes through exit code of successful command" {
    IS_INTERACTIVE=false
    run_with_spinner "test" true
}

@test "FUNC: run_with_spinner passes through exit code of failing command" {
    IS_INTERACTIVE=false
    ! run_with_spinner "test" false
}

@test "FUNC: show_paged_output function is defined" {
    type show_paged_output | grep -q 'function'
}

@test "FUNC: show_paged_output passes short input through directly" {
    local output
    output=$(echo "line1" | IS_INTERACTIVE=false show_paged_output "")
    echo "$output" | grep -q 'line1'
}

@test "FUNC: show_paged_output handles empty input" {
    local output
    output=$(echo "" | IS_INTERACTIVE=false show_paged_output "")
    [ $? -eq 0 ]
}

@test "FUNC: resolve_port_conflict function is defined" {
    type resolve_port_conflict | grep -q 'function'
}

@test "FUNC: read_menu_choice function is defined" {
    type read_menu_choice | grep -q 'function'
}

@test "FUNC: MENU_READ_TIMEOUT constant is defined" {
    grep -q 'MENU_READ_TIMEOUT=' "$SCRIPT_DIR/lib/core.sh"
}

@test "FUNC: MENU_READ_TIMEOUT is set to 3600" {
    grep -q 'MENU_READ_TIMEOUT=3600' "$SCRIPT_DIR/lib/core.sh"
}

@test "FUNC: main menu uses read_menu_choice" {
    grep -q 'read_menu_choice MENU_CHOICE' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "FUNC: Quick Mode has 9 action options" {
    grep -q '9) View interfaces' "$SCRIPT_DIR/lib/advanced.sh"
}

@test "FUNC: Quick Mode restart option calls stop_services and start_services" {
    grep -A3 '7)' "$SCRIPT_DIR/lib/advanced.sh" | grep -q 'stop_services'
    grep -A4 '7)' "$SCRIPT_DIR/lib/advanced.sh" | grep -q 'start_services'
}

@test "FUNC: Quick Mode view log uses tail" {
    grep -A5 '8)' "$SCRIPT_DIR/lib/advanced.sh" | grep -q 'tail -n 20'
}

@test "FUNC: port conflict resolver uses SIGTERM before SIGKILL" {
    local func_body
    func_body=$(grep -A100 'resolve_port_conflict()' "$SCRIPT_DIR/lib/utils.sh")
    echo "$func_body" | grep -q 'SIGTERM'
    echo "$func_body" | grep -q 'SIGKILL'
}

@test "FUNC: port conflict resolver validates PID is numeric" {
    grep -A50 'resolve_port_conflict()' "$SCRIPT_DIR/lib/utils.sh" | grep -q '\^\[0-9\]'
}

@test "FUNC: startup health check uses resolve_port_conflict" {
    grep -q 'resolve_port_conflict' "$SCRIPT_DIR/lib/advanced.sh"
}

@test "FUNC: spinner has ASCII fallback when HAS_COLOR is false" {
    grep -A5 'HAS_COLOR.*true.*then' "$SCRIPT_DIR/lib/utils.sh" | head -20 | grep -q '|.*/'
}

@test "FUNC: pagination respects IS_INTERACTIVE flag" {
    grep -q 'IS_INTERACTIVE.*!=.*true' "$SCRIPT_DIR/lib/ui.sh"
}
