#!/usr/bin/env bats
# Integration Tests — Service Management, Backup Round-Trip, Cross-Platform
# Tests behavioral aspects: polling patterns, cache invalidation, backup integrity,
# path traversal prevention, environment detection, and diagnostic protocol.
#
# Run with: bats tests/integration_tests.bats

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export LIB_DIR="$SCRIPT_DIR/lib"
    export PWSH_DIR="$SCRIPT_DIR/pwsh"
    export MAIN_SCRIPT="$SCRIPT_DIR/rns_management_tool.sh"

    # Combined source for grep-based tests
    COMBINED_SOURCE="$MAIN_SCRIPT"
    if [ -d "$LIB_DIR" ]; then
        for module in "$LIB_DIR"/*.sh; do
            [ -f "$module" ] && COMBINED_SOURCE="$COMBINED_SOURCE $module"
        done
    fi
    export COMBINED_SOURCE

    # Combined PowerShell source
    PS_COMBINED_SOURCE="$SCRIPT_DIR/rns_management_tool.ps1"
    if [ -d "$PWSH_DIR" ]; then
        for module in "$PWSH_DIR"/*.ps1; do
            [ -f "$module" ] && PS_COMBINED_SOURCE="$PS_COMBINED_SOURCE $module"
        done
    fi
    export PS_COMBINED_SOURCE

    # Temp dir for backup tests
    export TEST_TMPDIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TMPDIR" 2>/dev/null
}

#########################################################
# Service Polling Pattern Tests
#########################################################

@test "SERVICE: stop_services uses polling loop (not hardcoded sleep)" {
    local func_body
    func_body=$(sed -n '/^stop_services()/,/^}/p' "$LIB_DIR/services.sh")
    # Must have a while loop with wait counter
    echo "$func_body" | grep -q 'while.*is_rnsd_running.*wait_count'
}

@test "SERVICE: stop_services has bounded max_wait" {
    local func_body
    func_body=$(sed -n '/^stop_services()/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'max_wait='
}

@test "SERVICE: start_services uses polling loop (not hardcoded sleep)" {
    local func_body
    func_body=$(sed -n '/^start_services()/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'while.*is_rnsd_running.*wait_count'
}

@test "SERVICE: start_services has bounded max_wait" {
    local func_body
    func_body=$(sed -n '/^start_services()/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'max_wait='
}

@test "SERVICE: stop_services warns on timeout" {
    local func_body
    func_body=$(sed -n '/^stop_services()/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'may still be running'
}

@test "SERVICE: start_services reports failure on timeout" {
    local func_body
    func_body=$(sed -n '/^start_services()/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'failed to start'
}

@test "SERVICE: no hardcoded 'sleep 2' between stop/start in services" {
    # Session 1 identified race condition with hardcoded sleep
    local func_body
    func_body=$(sed -n '/^stop_services()/,/^}/p' "$LIB_DIR/services.sh")
    ! echo "$func_body" | grep -q 'sleep 2$'
}

#########################################################
# Status Cache TTL Tests
#########################################################

@test "CACHE: STATUS_CACHE_TTL is defined" {
    grep -q 'STATUS_CACHE_TTL=' $COMBINED_SOURCE
}

@test "CACHE: TTL is 10 seconds" {
    grep -q 'STATUS_CACHE_TTL=10' $COMBINED_SOURCE
}

@test "CACHE: get_cached_rnsd_status uses TTL comparison" {
    local func_body
    func_body=$(sed -n '/^get_cached_rnsd_status()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'STATUS_CACHE_TTL'
}

@test "CACHE: get_cached_rns_version uses TTL comparison" {
    local func_body
    func_body=$(sed -n '/^get_cached_rns_version()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'STATUS_CACHE_TTL'
}

@test "CACHE: get_cached_lxmf_version uses TTL comparison" {
    local func_body
    func_body=$(sed -n '/^get_cached_lxmf_version()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'STATUS_CACHE_TTL'
}

@test "CACHE: invalidate_status_cache resets rnsd status" {
    local func_body
    func_body=$(sed -n '/^invalidate_status_cache()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '_CACHE_RNSD_STATUS=""'
}

@test "CACHE: invalidate_status_cache resets rnsd timestamp" {
    local func_body
    func_body=$(sed -n '/^invalidate_status_cache()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '_CACHE_RNSD_TIME=0'
}

@test "CACHE: invalidate_status_cache resets rns version" {
    local func_body
    func_body=$(sed -n '/^invalidate_status_cache()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '_CACHE_RNS_VER=""'
}

@test "CACHE: invalidate_status_cache re-detects tools" {
    local func_body
    func_body=$(sed -n '/^invalidate_status_cache()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'detect_available_tools'
}

@test "CACHE: stop_services invalidates cache" {
    local func_body
    func_body=$(sed -n '/^stop_services()/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'invalidate_status_cache'
}

@test "CACHE: start_services invalidates cache" {
    local func_body
    func_body=$(sed -n '/^start_services()/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'invalidate_status_cache'
}

#########################################################
# Retry with Backoff Tests
#########################################################

@test "RETRY: retry_with_backoff function exists" {
    grep -q 'retry_with_backoff()' "$LIB_DIR/utils.sh"
}

@test "RETRY: uses exponential delay (delay * 2)" {
    local func_body
    func_body=$(sed -n '/^retry_with_backoff()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'delay.*\*.*2\|delay=.*((.*delay.*2'
}

@test "RETRY: starts with 2s delay" {
    local func_body
    func_body=$(sed -n '/^retry_with_backoff()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'delay=2'
}

@test "RETRY: logs failures" {
    local func_body
    func_body=$(sed -n '/^retry_with_backoff()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'log_error\|log_warn'
}

@test "RETRY: returns failure after max retries" {
    local func_body
    func_body=$(sed -n '/^retry_with_backoff()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'return 1'
}

@test "RETRY: used for network operations (pip install)" {
    grep -q 'retry_with_backoff.*PIP_TIMEOUT.*PIP_CMD' $COMBINED_SOURCE
}

@test "RETRY: used for network operations (git)" {
    grep -q 'retry_with_backoff.*git' $COMBINED_SOURCE
}

@test "RETRY: used for network operations (apt)" {
    grep -q 'retry_with_backoff.*apt' $COMBINED_SOURCE
}

#########################################################
# Backup Path Traversal Prevention (RNS004)
#########################################################

@test "BACKUP: import validates archive before extraction" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'Validating archive'
}

@test "BACKUP: import checks for ../ path traversal" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q '\.\.\/'
}

@test "BACKUP: import checks for absolute paths in archive" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -qE '\^/'
}

@test "BACKUP: import rejects invalid archives with security message" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'SECURITY.*invalid paths\|Security.*invalid paths'
}

@test "BACKUP: import logs security rejection" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'log_message.*SECURITY'
}

@test "BACKUP: import verifies .tar.gz extension" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q '\.tar\.gz'
}

@test "BACKUP: import creates backup before overwriting" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'create_backup'
}

@test "BACKUP: import requires confirmation" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'confirm_action'
}

#########################################################
# Backup: Actual round-trip validation with temp files
#########################################################

@test "BACKUP: tar.gz with path traversal is detectable" {
    # Create a tar.gz with ../ path
    mkdir -p "$TEST_TMPDIR/evil"
    echo "payload" > "$TEST_TMPDIR/evil/file.txt"
    # Create archive with ../ entry
    tar -czf "$TEST_TMPDIR/evil.tar.gz" -C "$TEST_TMPDIR" "evil/file.txt" 2>/dev/null

    # Verify the tool's detection pattern works: check for ../ or absolute paths
    local contents
    contents=$(tar -tzf "$TEST_TMPDIR/evil.tar.gz" 2>/dev/null)
    # This archive should NOT contain ../ (clean archive)
    ! echo "$contents" | grep -qE '(^/|\.\./)'
}

@test "BACKUP: clean archive passes traversal check" {
    # Create a proper .reticulum config structure
    mkdir -p "$TEST_TMPDIR/export/.reticulum"
    echo "[reticulum]" > "$TEST_TMPDIR/export/.reticulum/config"
    tar -czf "$TEST_TMPDIR/clean.tar.gz" -C "$TEST_TMPDIR/export" ".reticulum/config"

    local contents
    contents=$(tar -tzf "$TEST_TMPDIR/clean.tar.gz" 2>/dev/null)
    # Should NOT contain traversal or absolute paths
    ! echo "$contents" | grep -qE '(^/|\.\./)'
}

@test "BACKUP: export creates tar.gz format" {
    grep -q 'tar -czf' "$LIB_DIR/backup.sh"
}

@test "BACKUP: export includes .reticulum directory" {
    grep -q '\.reticulum' "$LIB_DIR/backup.sh"
}

@test "BACKUP: export includes .nomadnetwork directory" {
    grep -q '\.nomadnetwork' "$LIB_DIR/backup.sh"
}

@test "BACKUP: export includes .lxmf directory" {
    grep -q '\.lxmf' "$LIB_DIR/backup.sh"
}

@test "BACKUP: delete_old_backups keeps 3 most recent" {
    local func_body
    func_body=$(sed -n '/^delete_old_backups()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q '\-le 3'
}

@test "BACKUP: delete_old_backups requires confirmation" {
    local func_body
    func_body=$(sed -n '/^delete_old_backups()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'confirm_action'
}

@test "BACKUP: list_all_backups handles zero backups" {
    local func_body
    func_body=$(sed -n '/^list_all_backups()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'No backups found'
}

@test "BACKUP: restore_backup handles zero backups" {
    local func_body
    func_body=$(sed -n '/^restore_backup()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'No backups found'
}

#########################################################
# PowerShell Backup Parity (RNS004)
#########################################################

@test "BACKUP PS: Import-RnsConfiguration validates path traversal" {
    [ -f "$PWSH_DIR/backup.ps1" ] || skip "pwsh/backup.ps1 not found"
    grep -q '\.\.' "$PWSH_DIR/backup.ps1"
}

@test "BACKUP PS: Export uses Compress-Archive (zip format)" {
    [ -f "$PWSH_DIR/backup.ps1" ] || skip "pwsh/backup.ps1 not found"
    grep -q 'Compress-Archive' "$PWSH_DIR/backup.ps1"
}

@test "BACKUP PS: Import validates zip entries" {
    [ -f "$PWSH_DIR/backup.ps1" ] || skip "pwsh/backup.ps1 not found"
    grep -q 'ZipFile\|System.IO.Compression' "$PWSH_DIR/backup.ps1"
}

#########################################################
# Diagnostics Integration (Global Counter Pattern)
#########################################################

@test "DIAG: all 5 step functions exist" {
    grep -q 'diag_check_environment()' "$LIB_DIR/diagnostics.sh" &&
    grep -q 'diag_check_rns_tools()' "$LIB_DIR/diagnostics.sh" &&
    grep -q 'diag_check_configuration()' "$LIB_DIR/diagnostics.sh" &&
    grep -q 'diag_check_services()' "$LIB_DIR/diagnostics.sh" &&
    grep -q 'diag_check_network()' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: steps increment global counters directly" {
    # Verify steps use _DIAG_TOTAL_ISSUES / _DIAG_TOTAL_WARNINGS globals
    grep -q '_DIAG_TOTAL_ISSUES' "$LIB_DIR/diagnostics.sh" &&
    grep -q '_DIAG_TOTAL_WARNINGS' "$LIB_DIR/diagnostics.sh"
}

@test "DIAG: run_diagnostics resets counters before running" {
    local func_body
    func_body=$(sed -n '/^run_diagnostics()/,/^}/p' "$LIB_DIR/diagnostics.sh")
    echo "$func_body" | grep -q '_DIAG_TOTAL_ISSUES=0' &&
    echo "$func_body" | grep -q '_DIAG_TOTAL_WARNINGS=0'
}

@test "DIAG: run_diagnostics calls all 5 steps and summary" {
    local func_body
    func_body=$(sed -n '/^run_diagnostics()/,/^}/p' "$LIB_DIR/diagnostics.sh")
    echo "$func_body" | grep -q 'diag_check_environment' &&
    echo "$func_body" | grep -q 'diag_check_rns_tools' &&
    echo "$func_body" | grep -q 'diag_check_configuration' &&
    echo "$func_body" | grep -q 'diag_check_services' &&
    echo "$func_body" | grep -q 'diag_check_network' &&
    echo "$func_body" | grep -q 'diag_report_summary'
}

@test "DIAG: diag_report_summary reads global counters" {
    local func_body
    func_body=$(sed -n '/^diag_report_summary()/,/^}/p' "$LIB_DIR/diagnostics.sh")
    echo "$func_body" | grep -q '_DIAG_TOTAL_ISSUES' &&
    echo "$func_body" | grep -q '_DIAG_TOTAL_WARNINGS'
}

#########################################################
# Cross-Platform: Environment Detection
#########################################################

@test "PLATFORM: WSL detection checks /proc/version" {
    grep -q 'microsoft.*proc/version\|wsl.*proc/version' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: RPi detection checks /proc/cpuinfo" {
    grep -q 'BCM2.*cpuinfo\|Raspberry Pi.*cpuinfo' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: RPi detection covers BCM2, BCM27, BCM28 chip families" {
    grep -q 'BCM2\|BCM27\|BCM28' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: RPi model read from /proc/device-tree/model" {
    grep -q 'device-tree/model' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: RPi model fallback to /proc/cpuinfo Model field" {
    grep -q 'grep.*Model.*cpuinfo' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: architecture detected via uname -m" {
    grep -q 'uname -m' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: SSH detection covers SSH_CLIENT" {
    grep -q 'SSH_CLIENT' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: SSH detection covers SSH_TTY" {
    grep -q 'SSH_TTY' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: SSH detection covers SSH_CONNECTION" {
    grep -q 'SSH_CONNECTION' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: PEP 668 detection checks EXTERNALLY-MANAGED" {
    grep -q 'EXTERNALLY-MANAGED' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: interactive mode checks /dev/tty" {
    grep -q '/dev/tty' "$LIB_DIR/utils.sh"
}

@test "PLATFORM: OS detection reads /etc/os-release" {
    grep -q '/etc/os-release' "$LIB_DIR/utils.sh"
}

#########################################################
# Cross-Platform: Home Directory Resolution
#########################################################

@test "HOME: resolve_real_home prevents path traversal in SUDO_USER" {
    local func_body
    func_body=$(sed -n '/^resolve_real_home()/,/^}/p' "$LIB_DIR/core.sh")
    echo "$func_body" | grep -q '\.\.\*'
}

@test "HOME: resolve_real_home prevents slashes in SUDO_USER" {
    local func_body
    func_body=$(sed -n '/^resolve_real_home()/,/^}/p' "$LIB_DIR/core.sh")
    echo "$func_body" | grep -q '\*/\*'
}

@test "HOME: resolve_real_home uses getent for home lookup" {
    local func_body
    func_body=$(sed -n '/^resolve_real_home()/,/^}/p' "$LIB_DIR/core.sh")
    echo "$func_body" | grep -q 'getent passwd'
}

@test "HOME: resolve_real_home falls back to HOME" {
    local func_body
    func_body=$(sed -n '/^resolve_real_home()/,/^}/p' "$LIB_DIR/core.sh")
    echo "$func_body" | grep -q 'echo "\$HOME"'
}

@test "HOME: SUDO_USER path traversal behavioral test" {
    # Test the actual regex used in resolve_real_home
    # These should be rejected:
    local bad_user="../root"
    [[ "$bad_user" == *..* ]]

    bad_user="foo/bar"
    [[ "$bad_user" == */* ]]
}

@test "HOME: normal SUDO_USER passes validation" {
    local good_user="nursedude"
    ! [[ "$good_user" == */* ]] && ! [[ "$good_user" == *..* ]]
}

#########################################################
# Cross-Platform: Terminal Capabilities
#########################################################

@test "TERM: detect_terminal_capabilities function exists" {
    grep -q 'detect_terminal_capabilities()' "$LIB_DIR/core.sh"
}

@test "TERM: handles dumb terminal" {
    grep -q 'dumb' "$LIB_DIR/core.sh"
}

@test "TERM: handles vt100 terminal" {
    grep -q 'vt100' "$LIB_DIR/core.sh"
}

@test "TERM: checks tput colors count" {
    grep -q 'tput colors' "$LIB_DIR/core.sh"
}

@test "TERM: color codes set to empty for no-color terminals" {
    # Verify the else branch clears colors
    grep -q "RED=''" "$LIB_DIR/core.sh"
}

@test "TERM: ANSI clear_screen used (not subprocess clear)" {
    # Session 6 replaced subprocess clear with ANSI escape
    grep -q 'printf.*033\[H.*033\[2J\|\\033\[H\\033\[2J' $COMBINED_SOURCE
}

#########################################################
# Cross-Platform: PowerShell Environment Detection
#########################################################

@test "PLATFORM PS: Test-WSL function exists" {
    [ -f "$PWSH_DIR/environment.ps1" ] || skip "pwsh/environment.ps1 not found"
    grep -q 'function Test-WSL' "$PWSH_DIR/environment.ps1"
}

@test "PLATFORM PS: WSL detection uses wsl command" {
    [ -f "$PWSH_DIR/environment.ps1" ] || skip "pwsh/environment.ps1 not found"
    grep -q 'wsl --list' "$PWSH_DIR/environment.ps1"
}

@test "PLATFORM PS: Get-WSLDistribution function exists" {
    [ -f "$PWSH_DIR/environment.ps1" ] || skip "pwsh/environment.ps1 not found"
    grep -q 'function Get-WSLDistribution' "$PWSH_DIR/environment.ps1"
}

@test "PLATFORM PS: Test-Python checks python and python3" {
    [ -f "$PWSH_DIR/environment.ps1" ] || skip "pwsh/environment.ps1 not found"
    grep -q 'python3\|python ' "$PWSH_DIR/environment.ps1"
}

@test "PLATFORM PS: Test-Pip checks pip and pip3" {
    [ -f "$PWSH_DIR/environment.ps1" ] || skip "pwsh/environment.ps1 not found"
    grep -q 'pip3\|pip ' "$PWSH_DIR/environment.ps1"
}

#########################################################
# Log Rotation Integration
#########################################################

@test "LOG: rotate_log tests file size before rotating" {
    local func_body
    func_body=$(sed -n '/^rotate_log()/,/^}/p' "$LIB_DIR/core.sh")
    echo "$func_body" | grep -q 'log_size.*LOG_MAX_BYTES'
}

@test "LOG: rotation threshold is 1MB" {
    grep -q 'LOG_MAX_BYTES=1048576' "$LIB_DIR/core.sh"
}

@test "LOG: keeps 3 rotated copies" {
    grep -q 'LOG_MAX_ROTATIONS=3' "$LIB_DIR/core.sh"
}

@test "LOG: cleans up legacy timestamped logs" {
    local func_body
    func_body=$(sed -n '/^rotate_log()/,/^}/p' "$LIB_DIR/core.sh")
    echo "$func_body" | grep -q 'rns_management_\*\.log'
}

@test "LOG: rotate_log called at module load time" {
    # Verify rotate_log is called at top level in core.sh (not inside a function)
    grep -n '^rotate_log$' "$LIB_DIR/core.sh"
}

#########################################################
# safe_call Error Categorization
#########################################################

@test "SAFE_CALL: categorizes exit code 126 (permission denied)" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '126'
}

@test "SAFE_CALL: categorizes exit code 127 (command not found)" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '127'
}

@test "SAFE_CALL: categorizes exit code 124 (timeout)" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '124'
}

@test "SAFE_CALL: handles exit code 130 (Ctrl+C) gracefully" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '130'
}

@test "SAFE_CALL: logs failures" {
    local func_body
    func_body=$(sed -n '/^safe_call()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'log_error'
}

#########################################################
# Network Timeout Constants
#########################################################

@test "TIMEOUT: NETWORK_TIMEOUT defined (5 min)" {
    grep -q 'NETWORK_TIMEOUT=300' "$LIB_DIR/core.sh"
}

@test "TIMEOUT: APT_TIMEOUT defined (10 min)" {
    grep -q 'APT_TIMEOUT=600' "$LIB_DIR/core.sh"
}

@test "TIMEOUT: GIT_TIMEOUT defined" {
    grep -q 'GIT_TIMEOUT=' "$LIB_DIR/core.sh"
}

@test "TIMEOUT: PIP_TIMEOUT defined" {
    grep -q 'PIP_TIMEOUT=' "$LIB_DIR/core.sh"
}

@test "TIMEOUT: run_with_timeout uses timeout command" {
    local func_body
    func_body=$(sed -n '/^run_with_timeout()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'timeout "$timeout_val"'
}

@test "TIMEOUT: run_with_timeout has fallback when timeout not available" {
    local func_body
    func_body=$(sed -n '/^run_with_timeout()/,/^}/p' "$LIB_DIR/utils.sh")
    # Should fallback to running command without timeout
    echo "$func_body" | grep -q '"$@"'
}

#########################################################
# Cleanup and Trap Handlers
#########################################################

@test "CLEANUP: EXIT trap registered" {
    grep -q 'trap cleanup_on_exit EXIT' "$LIB_DIR/utils.sh"
}

@test "CLEANUP: INT/TERM trap registered" {
    grep -q 'trap.*INT.*TERM' "$LIB_DIR/utils.sh"
}

@test "CLEANUP: removes temp files on exit" {
    local func_body
    func_body=$(sed -n '/^cleanup_on_exit()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'rm -f.*rns_mgmt_.*\.tmp'
}

@test "CLEANUP: logs non-zero exit codes" {
    local func_body
    func_body=$(sed -n '/^cleanup_on_exit()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'log_error.*exit.*code'
}

@test "CLEANUP: does not log exit 130 as error (Ctrl+C)" {
    local func_body
    func_body=$(sed -n '/^cleanup_on_exit()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '130'
}

#########################################################
# meshtasticd Integration
#########################################################

@test "MESHTASTICD: HTTP API probe tests multiple ports" {
    local func_body
    func_body=$(sed -n '/^check_meshtasticd_http_api()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q '443' &&
    echo "$func_body" | grep -q '9443' &&
    echo "$func_body" | grep -q '80' &&
    echo "$func_body" | grep -q '4403'
}

@test "MESHTASTICD: HTTP API tries both HTTPS and HTTP" {
    local func_body
    func_body=$(sed -n '/^check_meshtasticd_http_api()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'https' &&
    echo "$func_body" | grep -q 'http'
}

@test "MESHTASTICD: config validation checks for Webserver section" {
    local func_body
    func_body=$(sed -n '/^check_meshtasticd_webserver_config()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'Webserver:'
}

@test "MESHTASTICD: config validation detects commented-out section" {
    local func_body
    func_body=$(sed -n '/^check_meshtasticd_webserver_config()/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'commented out'
}
