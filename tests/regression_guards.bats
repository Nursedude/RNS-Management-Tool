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

#########################################################
# MeshForge cross-pollination — Session 1 (R3, R7, R8, R9)
#########################################################

# R9: --rnode CLI flag

@test "CLI: --rnode flag handled in main script" {
    grep -q '\-\-rnode' "$SCRIPT_DIR/rns_management_tool.sh"
}

@test "CLI: --rnode calls configure_rnode_interactive" {
    # The --rnode case block must call configure_rnode_interactive
    local rnode_block
    rnode_block=$(sed -n '/--rnode)/,/;;/p' "$SCRIPT_DIR/rns_management_tool.sh")
    echo "$rnode_block" | grep -q 'configure_rnode_interactive'
}

@test "CLI: --rnode listed in --help output" {
    # Verify --rnode appears in the help text section (between --help and exit 0)
    local help_block
    help_block=$(sed -n '/--help, -h/,/exit 0/p' "$SCRIPT_DIR/rns_management_tool.sh")
    echo "$help_block" | grep -q '\-\-rnode'
}

# R7: No curl-pipe-bash in PowerShell WSL integration

@test "PWSH: no curl pipe to bash in install.ps1" {
    ! grep -q '| bash' "$PWSH_DIR/install.ps1"
}

@test "PWSH: no curl pipe to bash in rnode.ps1" {
    ! grep -q '| bash' "$PWSH_DIR/rnode.ps1"
}

@test "PWSH: install.ps1 downloads to temp file before executing" {
    grep -q 'mktemp' "$PWSH_DIR/install.ps1"
}

@test "PWSH: rnode.ps1 downloads to temp file before executing" {
    grep -q 'mktemp' "$PWSH_DIR/rnode.ps1"
}

# R8: No duplicate Export/Import in advanced.ps1

@test "PWSH: no Export-Configuration function in advanced.ps1" {
    ! grep -qP '^\s*function Export-Configuration\b' "$PWSH_DIR/advanced.ps1"
}

@test "PWSH: no Import-Configuration function in advanced.ps1" {
    ! grep -qP '^\s*function Import-Configuration\b' "$PWSH_DIR/advanced.ps1"
}

@test "PWSH: advanced menu calls Export-RnsConfiguration from backup.ps1" {
    grep -q 'Export-RnsConfiguration' "$PWSH_DIR/advanced.ps1"
}

@test "PWSH: advanced menu calls Import-RnsConfiguration from backup.ps1" {
    grep -q 'Import-RnsConfiguration' "$PWSH_DIR/advanced.ps1"
}

# R3: Restrictive umask for backup operations

@test "BACKUP: create_backup sets restrictive umask" {
    grep -q 'umask 077' "$LIB_DIR/backup.sh"
}

@test "BACKUP: create_backup restores original umask" {
    local func_body
    func_body=$(sed -n '/^create_backup()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'umask "$old_umask"'
}

@test "BACKUP: export_configuration sets restrictive umask" {
    local func_body
    func_body=$(sed -n '/^export_configuration()/,/^}/p' "$LIB_DIR/backup.sh")
    echo "$func_body" | grep -q 'umask 077'
}

# R1: NodeSource download validation

@test "INSTALL: NodeSource download has size validation" {
    grep -q 'script_size' "$LIB_DIR/install.sh"
}

@test "INSTALL: NodeSource download logs SHA256" {
    grep -q 'sha256sum' "$LIB_DIR/install.sh"
}

#########################################################
# Linter Rules RNS009-RNS010
#########################################################

@test "LINTER: scripts/lint.sh defines RNS009 rule" {
    grep -q 'RNS009' "$SCRIPT_DIR/scripts/lint.sh"
}

@test "LINTER: scripts/lint.sh defines RNS010 rule" {
    grep -q 'RNS010' "$SCRIPT_DIR/scripts/lint.sh"
}

@test "RNS009: no hardcoded /tmp paths in lib/ modules (use mktemp)" {
    # Scan all lib/ modules for hardcoded /tmp/ that aren't using ${TMPDIR:-/tmp}
    local violations=0
    for module in "$LIB_DIR"/*.sh; do
        while IFS= read -r line; do
            local stripped="${line#"${line%%[![:space:]]*}"}"
            [[ "$stripped" == "#"* ]] && continue
            if [[ "$line" =~ /tmp/[a-zA-Z_\$] ]] && \
               [[ "$line" != *'${TMPDIR:-/tmp}'* ]] && \
               [[ "$line" != *'TMPDIR'* ]] && \
               [[ "$line" != *"grep"* ]] && [[ "$line" != *"echo"* ]] && \
               [[ "$line" != *"mktemp"* ]]; then
                ((violations++))
            fi
        done < "$module"
    done
    [ "$violations" -eq 0 ]
}

@test "RNS010: no sensitive keywords in log calls in lib/ modules" {
    local violations=0
    for module in "$LIB_DIR"/*.sh; do
        while IFS= read -r line; do
            local stripped="${line#"${line%%[![:space:]]*}"}"
            [[ "$stripped" == "#"* ]] && continue
            if [[ "$line" =~ log_(message|debug|warn|error) ]] && \
               [[ "$line" =~ (password|secret|token|credential|private_key) ]]; then
                ((violations++))
            fi
        done < "$module"
    done
    [ "$violations" -eq 0 ]
}

@test "LINTER: linter passes cleanly on all lib/ modules" {
    bash "$SCRIPT_DIR/scripts/lint.sh" "$LIB_DIR"/*.sh
}

#########################################################
# RNS011: Operator-personal values (hardcoded /home/<user>/ paths)
#########################################################

@test "RNS011: linter flags hardcoded /home/<user>/ path" {
    local tmpfile
    tmpfile=$(mktemp "${BATS_TMPDIR:-/tmp}/rns011_bad_XXXXXX.sh")
    cat > "$tmpfile" <<'EOF'
#!/bin/bash
CONFIG="/home/someoperator/.reticulum/config"
EOF
    local output
    output=$(bash "$SCRIPT_DIR/scripts/lint.sh" "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    [[ "$output" == *"RNS011"* ]]
}

@test "RNS011: linter accepts \$HOME-based path" {
    local tmpfile
    tmpfile=$(mktemp "${BATS_TMPDIR:-/tmp}/rns011_good_XXXXXX.sh")
    cat > "$tmpfile" <<'EOF'
#!/bin/bash
CONFIG="$HOME/.reticulum/config"
ALT="${REAL_HOME}/.reticulum/config"
EOF
    local output
    output=$(bash "$SCRIPT_DIR/scripts/lint.sh" "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    [[ "$output" != *"RNS011"* ]]
}

#########################################################
# Reliability: install pipelines must check exit codes
#########################################################

@test "Sideband install: git pull is wrapped in error-checking conditional" {
    # Regression for: bare `retry... | tee ...` would let stale-tree pip install run
    # silently when the upstream pull failed.
    grep -q 'if ! retry_with_backoff.*git pull origin main' "$LIB_DIR/install.sh"
}

#########################################################
# Partial-install rollback (cleanup_partial_install helper)
#########################################################

@test "ROLLBACK: cleanup_partial_install helper exists in lib/install.sh" {
    grep -q '^cleanup_partial_install()' "$LIB_DIR/install.sh"
}

@test "ROLLBACK: cleanup helper preserves dir on update failure" {
    # Source the helper in isolation and verify it does NOT remove the dir
    # when called with is_update=true.
    local tmpdir
    tmpdir=$(mktemp -d "${BATS_TMPDIR:-/tmp}/rollback_update_XXXXXX")
    touch "$tmpdir/sentinel"
    # Stub helpers the function calls so we can source-and-call standalone
    print_info() { :; }
    print_warning() { :; }
    print_success() { :; }
    log_message() { :; }
    log_warn() { :; }
    # shellcheck source=/dev/null
    source <(sed -n '/^cleanup_partial_install()/,/^}/p' "$LIB_DIR/install.sh")
    cleanup_partial_install "TestComponent" "$tmpdir" "true"
    [ -f "$tmpdir/sentinel" ]
    rm -rf "$tmpdir"
}

@test "ROLLBACK: cleanup helper removes dir on first-install failure" {
    local tmpdir
    tmpdir=$(mktemp -d "${BATS_TMPDIR:-/tmp}/rollback_install_XXXXXX")
    touch "$tmpdir/sentinel"
    print_info() { :; }
    print_warning() { :; }
    print_success() { :; }
    log_message() { :; }
    log_warn() { :; }
    # shellcheck source=/dev/null
    source <(sed -n '/^cleanup_partial_install()/,/^}/p' "$LIB_DIR/install.sh")
    cleanup_partial_install "TestComponent" "$tmpdir" "false"
    [ ! -d "$tmpdir" ]
}

@test "ROLLBACK: install_meshchat invokes cleanup on every hard-failure branch" {
    # Hard failures: clone (step 1), npm install (step 2), build-frontend (step 4).
    # Step 3 (pip requirements) is intentionally a soft warn — exempt.
    local meshchat_block
    meshchat_block=$(sed -n '/^install_meshchat()/,/^}/p' "$LIB_DIR/install.sh")
    local invocations
    invocations=$(grep -c 'cleanup_partial_install "MeshChat"' <<<"$meshchat_block")
    [ "$invocations" -ge 3 ]
}

@test "ROLLBACK: install_sideband_source invokes cleanup on every hard-failure branch" {
    # Hard failures: clone, git pull, pip install . — all three need cleanup.
    local sideband_block
    sideband_block=$(sed -n '/^install_sideband_source()/,/^}/p' "$LIB_DIR/install.sh")
    local invocations
    invocations=$(grep -c 'cleanup_partial_install "Sideband"' <<<"$sideband_block")
    [ "$invocations" -ge 3 ]
}

@test "ROLLBACK: install_sideband_source tracks is_update so cleanup can branch on it" {
    grep -q 'local is_update=false' <(sed -n '/^install_sideband_source()/,/^}/p' "$LIB_DIR/install.sh")
}
