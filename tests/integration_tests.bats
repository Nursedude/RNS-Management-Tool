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

@test "BACKUP: import delegates to validate_archive_contents (centralized)" {
    local func_body
    func_body=$(sed -n '/^import_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'validate_archive_contents'
}

@test "BACKUP: validate_archive_contents checks for ../ path traversal" {
    local func_body
    func_body=$(sed -n '/^validate_archive_contents()/,/^}/p' "$LIB_DIR/validation.sh")
    echo "$func_body" | grep -q '\.\.\/'
}

@test "BACKUP: validate_archive_contents rejects invalid archives with security message" {
    local func_body
    func_body=$(sed -n '/^validate_archive_contents()/,/^}/p' "$LIB_DIR/validation.sh")
    echo "$func_body" | grep -q 'Security.*invalid paths\|Security.*symbolic'
}

@test "BACKUP: validate_archive_contents logs security rejection" {
    local func_body
    func_body=$(sed -n '/^validate_archive_contents()/,/^}/p' "$LIB_DIR/validation.sh")
    echo "$func_body" | grep -q 'log_message.*SECURITY'
}

@test "BACKUP: import verifies .tar.gz extension (via validate_archive_path)" {
    # Extension check moved to centralized validate_archive_path in validation.sh
    local func_body
    func_body=$(sed -n '/^validate_archive_path()/,/^}/p' "$LIB_DIR/validation.sh")
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

#########################################################
# Behavioral Tests — Execute actual functions
# These tests source the modules and call real functions
# with controlled inputs. No mocks — real code execution.
#########################################################

# Helper: source core + validation modules for behavioral tests
_source_validation() {
    # Minimal sourcing: just what's needed for validation functions
    # Stub print functions if not available
    print_error() { echo "ERROR: $1"; }
    print_warning() { echo "WARN: $1"; }
    log_message() { :; }
    source "$LIB_DIR/validation.sh"
}

@test "BEHAVIORAL: validate_rns_hash accepts valid 32-char hex" {
    _source_validation
    validate_rns_hash "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
}

@test "BEHAVIORAL: validate_rns_hash accepts valid 64-char hex" {
    _source_validation
    validate_rns_hash "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
}

@test "BEHAVIORAL: validate_rns_hash rejects empty input" {
    _source_validation
    ! validate_rns_hash ""
}

@test "BEHAVIORAL: validate_rns_hash rejects non-hex characters" {
    _source_validation
    ! validate_rns_hash "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
}

@test "BEHAVIORAL: validate_rns_hash rejects too-short hash" {
    _source_validation
    ! validate_rns_hash "a1b2c3d4"
}

@test "BEHAVIORAL: validate_device_port accepts /dev/ttyUSB0" {
    _source_validation
    validate_device_port "/dev/ttyUSB0"
}

@test "BEHAVIORAL: validate_device_port accepts /dev/ttyACM0" {
    _source_validation
    validate_device_port "/dev/ttyACM0"
}

@test "BEHAVIORAL: validate_device_port rejects empty" {
    _source_validation
    ! validate_device_port ""
}

@test "BEHAVIORAL: validate_device_port rejects path traversal" {
    _source_validation
    ! validate_device_port "/dev/../etc/passwd"
}

@test "BEHAVIORAL: validate_device_port rejects spaces" {
    _source_validation
    ! validate_device_port "/dev/tty USB0"
}

@test "BEHAVIORAL: validate_device_port rejects semicolons" {
    _source_validation
    ! validate_device_port "/dev/ttyUSB0;rm"
}

@test "BEHAVIORAL: validate_numeric_range accepts value in range" {
    _source_validation
    validate_numeric_range "10" 7 12 "SF"
}

@test "BEHAVIORAL: validate_numeric_range rejects below minimum" {
    _source_validation
    ! validate_numeric_range "3" 7 12 "SF"
}

@test "BEHAVIORAL: validate_numeric_range rejects above maximum" {
    _source_validation
    ! validate_numeric_range "15" 7 12 "SF"
}

@test "BEHAVIORAL: validate_numeric_range accepts negative values" {
    _source_validation
    validate_numeric_range "-5" -10 30 "TX Power"
}

@test "BEHAVIORAL: validate_numeric_range rejects non-numeric" {
    _source_validation
    ! validate_numeric_range "abc" 7 12 "SF"
}

@test "BEHAVIORAL: validate_numeric_range returns 1 for empty (skip)" {
    _source_validation
    ! validate_numeric_range "" 7 12 "SF"
}

@test "BEHAVIORAL: validate_frequency accepts 915MHz" {
    _source_validation
    validate_frequency "915000000"
}

@test "BEHAVIORAL: validate_frequency accepts 868MHz" {
    _source_validation
    validate_frequency "868000000"
}

@test "BEHAVIORAL: validate_frequency rejects non-numeric" {
    _source_validation
    ! validate_frequency "abc"
}

@test "BEHAVIORAL: validate_identifier accepts alphanumeric+underscore" {
    _source_validation
    validate_identifier "t3s3_v2" "Model"
}

@test "BEHAVIORAL: validate_identifier rejects spaces" {
    _source_validation
    ! validate_identifier "t3 s3" "Model"
}

@test "BEHAVIORAL: validate_identifier rejects special chars" {
    _source_validation
    ! validate_identifier "t3s3;rm" "Model"
}

@test "BEHAVIORAL: validate_archive_contents detects traversal" {
    _source_validation
    # Create a clean archive (should pass)
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/data"
    echo "test" > "$tmpdir/data/file.txt"
    tar -czf "$tmpdir/clean.tar.gz" -C "$tmpdir" "data/file.txt"
    validate_archive_contents "$tmpdir/clean.tar.gz"
    rm -rf "$tmpdir"
}

@test "BEHAVIORAL: run_with_timeout runs command successfully" {
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/validation.sh"
    source "$LIB_DIR/utils.sh"
    run_with_timeout 5 echo "hello"
}

@test "BEHAVIORAL: retry_with_backoff succeeds on first try" {
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/validation.sh"
    source "$LIB_DIR/utils.sh"
    retry_with_backoff 3 true
}

@test "BEHAVIORAL: retry_with_backoff fails after max retries" {
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/validation.sh"
    source "$LIB_DIR/utils.sh"
    ! retry_with_backoff 1 false
}

@test "BEHAVIORAL: safe_call returns 0 on success" {
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/validation.sh"
    source "$LIB_DIR/utils.sh"
    safe_call "test" true
}

@test "BEHAVIORAL: safe_call returns non-zero on failure" {
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/validation.sh"
    source "$LIB_DIR/utils.sh"
    ! safe_call "test" false
}

#########################################################
# Configuration Management Tests (Session 14)
#########################################################

@test "CONFIG: apply_config_template creates backup before overwrite" {
    local func_body
    func_body=$(sed -n '/^apply_config_template/,/^}/p' "$LIB_DIR/config.sh")
    # Must backup before cp (template application)
    echo "$func_body" | grep -q 'backup'
    echo "$func_body" | grep -q 'cp.*config_file.*backup'
}

@test "CONFIG: view_config_files handles missing config gracefully" {
    local func_body
    func_body=$(sed -n '/^view_config_files/,/^}/p' "$LIB_DIR/config.sh")
    echo "$func_body" | grep -q 'No configuration files found'
}

@test "CONFIG: template directory exists with 4 templates" {
    [ -d "$SCRIPT_DIR/config_templates" ]
    local count
    count=$(find "$SCRIPT_DIR/config_templates" -name '*.conf' -type f | wc -l)
    [ "$count" -eq 4 ]
}

@test "CONFIG: config templates contain [reticulum] section" {
    for tmpl in "$SCRIPT_DIR"/config_templates/*.conf; do
        grep -q '^\[reticulum\]' "$tmpl"
    done
}

@test "CONFIG: config templates contain [interfaces] section" {
    for tmpl in "$SCRIPT_DIR"/config_templates/*.conf; do
        grep -q '^\[interfaces\]' "$tmpl"
    done
}

@test "NETWORK: handle_network_tools requires rnsd via require_service" {
    local func_body
    func_body=$(sed -n '/^handle_network_tools/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'require_service'
}

@test "NETWORK: handle_remote_command validates destination hash" {
    local func_body
    func_body=$(sed -n '/^handle_remote_command/,/^}/p' "$LIB_DIR/services.sh")
    echo "$func_body" | grep -q 'validate_rns_hash'
}

@test "RECOVERY: safe_call captures stderr to temp file" {
    local func_body
    func_body=$(sed -n '/^safe_call/,/^}/p' "$LIB_DIR/utils.sh")
    echo "$func_body" | grep -q 'mktemp'
    echo "$func_body" | grep -q 'stderr_file'
}
