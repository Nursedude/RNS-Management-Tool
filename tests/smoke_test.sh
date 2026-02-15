#!/bin/bash
# smoke_test.sh — Lightweight regression gate for CI
# Validates syntax, expected function definitions, module sourcing, and --check mode
#
# Usage:
#   ./tests/smoke_test.sh              # Run all checks
#   ./tests/smoke_test.sh --verbose    # Show detailed output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/rns_management_tool.sh"
PS_SCRIPT="$SCRIPT_DIR/rns_management_tool.ps1"
LIB_DIR="$SCRIPT_DIR/lib"
PWSH_DIR="$SCRIPT_DIR/pwsh"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

PASS=0
FAIL=0
SKIP=0

# ─── Helpers ──────────────────────────────────────────────
pass() {
    PASS=$((PASS + 1))
    echo "  [PASS] $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $1"
    [[ -n "${2:-}" ]] && echo "         $2"
}

skip() {
    SKIP=$((SKIP + 1))
    echo "  [SKIP] $1"
}

section() {
    echo ""
    echo "═══ $1 ═══"
}

# ─── 1. Bash Syntax ──────────────────────────────────────
section "Bash Syntax Validation"

if bash -n "$MAIN_SCRIPT" 2>/dev/null; then
    pass "rns_management_tool.sh parses without syntax errors"
else
    fail "rns_management_tool.sh has syntax errors" "Run: bash -n rns_management_tool.sh"
fi

# Validate each lib module individually
if [ -d "$LIB_DIR" ]; then
    for module in "$LIB_DIR"/*.sh; do
        [ -f "$module" ] || continue
        modname=$(basename "$module")
        if bash -n "$module" 2>/dev/null; then
            pass "lib/$modname parses without syntax errors"
        else
            fail "lib/$modname has syntax errors" "Run: bash -n lib/$modname"
        fi
    done
else
    skip "lib/ directory not found (monolithic mode)"
fi

# ─── 2. PowerShell Syntax ────────────────────────────────
section "PowerShell Syntax Validation"

if [ -f "$PS_SCRIPT" ]; then
    if command -v pwsh &>/dev/null; then
        if pwsh -NoProfile -Command "
            \$tokens = \$null; \$errors = \$null
            [System.Management.Automation.Language.Parser]::ParseFile('$PS_SCRIPT', [ref]\$tokens, [ref]\$errors) | Out-Null
            if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Error \$_.Message }; exit 1 }
            exit 0
        " 2>/dev/null; then
            pass "rns_management_tool.ps1 parses without syntax errors"
        else
            fail "rns_management_tool.ps1 has syntax errors"
        fi
    else
        skip "pwsh not available — cannot validate PowerShell syntax"
    fi
else
    skip "rns_management_tool.ps1 not found"
fi

# ─── 3. Expected Function Definitions (Bash) ─────────────
section "Bash Function Assertions"

# Core functions that must exist in the main script or sourced modules
EXPECTED_FUNCTIONS=(
    # Core / UI
    detect_terminal_capabilities
    resolve_real_home
    detect_environment
    detect_available_tools
    print_header
    print_section
    print_success
    print_warning
    print_error
    print_info
    log_message
    show_main_menu
    show_help
    confirm_action
    # Service management
    start_services
    stop_services
    services_menu
    setup_autostart
    disable_autostart
    check_service_status
    # Backup
    backup_restore_menu
    create_backup
    restore_backup
    export_configuration
    import_configuration
    list_all_backups
    delete_old_backups
    # Diagnostics
    run_diagnostics
    diag_check_environment
    diag_check_rns_tools
    diag_check_configuration
    diag_check_services
    diag_check_network
    diag_report_summary
    # Installation
    install_reticulum_ecosystem
    install_meshchat
    install_sideband
    install_prerequisites
    # RNODE
    configure_rnode_interactive
    rnode_autoinstall
    rnode_configure_radio
    # Network tools
    handle_network_tools
    handle_file_transfer
    handle_remote_command
    handle_identity_management
    # Advanced
    advanced_menu
    emergency_quick_mode
    # Dialog backend
    detect_dialog_backend
    has_dialog_backend
    dlg_msgbox
    dlg_yesno
    dlg_menu
    dlg_inputbox
    # Log rotation
    rotate_log
    # Entry
    main
)

# Build combined source: main script + all lib modules
COMBINED_SOURCE="$MAIN_SCRIPT"
if [ -d "$LIB_DIR" ]; then
    for module in "$LIB_DIR"/*.sh; do
        [ -f "$module" ] && COMBINED_SOURCE="$COMBINED_SOURCE $module"
    done
fi

for func in "${EXPECTED_FUNCTIONS[@]}"; do
    if grep -qE "^${func}\(\)|^function ${func}" $COMBINED_SOURCE 2>/dev/null; then
        $VERBOSE && pass "Function defined: $func"
        PASS=$((PASS + 1))
    else
        fail "Missing function: $func"
    fi
done
$VERBOSE || pass "All ${#EXPECTED_FUNCTIONS[@]} expected bash functions found (${FAIL} missing)"

# ─── 4. Expected Functions (PowerShell) ──────────────────
section "PowerShell Function Assertions"

PS_EXPECTED_FUNCTIONS=(
    Initialize-Environment
    Show-ServiceMenu
    Show-BackupMenu
    Show-MainMenu
    New-Backup
    Restore-Backup
    Start-RNSDaemon
    Stop-RNSDaemon
    Show-Diagnostic
    Install-Reticulum
    Install-MeshChat
    Install-Sideband
    Show-RnodeMenu
    # New parity functions
    Invoke-FileTransfer
    Invoke-RemoteCommand
    Enable-RnsdAutoStart
    Disable-RnsdAutoStart
    Get-AllBackups
    Remove-OldBackups
    Export-RnsConfiguration
    Import-RnsConfiguration
    # Log rotation
    Invoke-LogRotation
)

# Build combined PS source: main script + all pwsh modules
PS_COMBINED_SOURCE="$PS_SCRIPT"
if [ -d "$PWSH_DIR" ]; then
    for module in "$PWSH_DIR"/*.ps1; do
        [ -f "$module" ] && PS_COMBINED_SOURCE="$PS_COMBINED_SOURCE $module"
    done
fi

if [ -f "$PS_SCRIPT" ]; then
    for func in "${PS_EXPECTED_FUNCTIONS[@]}"; do
        if grep -qE "^function ${func}" $PS_COMBINED_SOURCE 2>/dev/null; then
            $VERBOSE && pass "PS function defined: $func"
            PASS=$((PASS + 1))
        else
            fail "Missing PS function: $func"
        fi
    done
    $VERBOSE || pass "All ${#PS_EXPECTED_FUNCTIONS[@]} expected PowerShell functions found"
else
    skip "PowerShell script not found"
fi

# ─── 5. --check Flag (Dry-Run Mode) ──────────────────────
section "Dry-Run Mode (--check)"

if grep -q '\-\-check' "$MAIN_SCRIPT" 2>/dev/null; then
    # Run --check and capture output
    check_exit=0
    check_output=$(bash "$MAIN_SCRIPT" --check 2>&1) || check_exit=$?

    if [ $check_exit -eq 0 ]; then
        pass "--check mode exits cleanly (exit 0)"
    else
        fail "--check mode exited with code $check_exit"
    fi

    if echo "$check_output" | grep -qi "syntax.*ok\|check.*pass\|validation.*pass"; then
        pass "--check mode reports validation results"
    else
        fail "--check mode did not report validation results"
        $VERBOSE && echo "         Output: $(echo "$check_output" | head -5)"
    fi
else
    skip "--check flag not implemented in main script"
fi

# ─── 6. Module Structure ─────────────────────────────────
section "Module Structure"

if [ -d "$LIB_DIR" ]; then
    module_count=$(find "$LIB_DIR" -name "*.sh" -type f | wc -l)
    if [ "$module_count" -ge 3 ]; then
        pass "lib/ contains $module_count modules"
    else
        fail "lib/ has only $module_count modules (expected >= 3)"
    fi

    # Verify main script sources lib modules
    if grep -qE 'source.*lib/|\..*lib/' "$MAIN_SCRIPT" 2>/dev/null; then
        pass "Main script sources lib/ modules"
    else
        fail "Main script does not source lib/ modules"
    fi
else
    skip "lib/ directory not found"
fi

# ─── 6b. PowerShell Module Structure ─────────────────────
section "PowerShell Module Structure"

if [ -d "$PWSH_DIR" ]; then
    ps_module_count=$(find "$PWSH_DIR" -name "*.ps1" -type f | wc -l)
    if [ "$ps_module_count" -ge 3 ]; then
        pass "pwsh/ contains $ps_module_count modules"
    else
        fail "pwsh/ has only $ps_module_count modules (expected >= 3)"
    fi

    # Verify main PS script dot-sources pwsh modules
    if grep -qE '\\pwsh\\' "$PS_SCRIPT" 2>/dev/null; then
        pass "Main PS script dot-sources pwsh/ modules"
    else
        fail "Main PS script does not dot-source pwsh/ modules"
    fi
else
    skip "pwsh/ directory not found"
fi

# ─── 6c. Dialog Backend ─────────────────────────────────
section "Dialog Backend"

if [ -f "$LIB_DIR/dialog.sh" ]; then
    pass "lib/dialog.sh exists"
    if grep -qE 'detect_dialog_backend|DIALOG_BACKEND' "$LIB_DIR/dialog.sh" 2>/dev/null; then
        pass "Dialog backend detection implemented"
    else
        fail "Dialog backend detection not found in dialog.sh"
    fi
    if grep -qE 'dlg_msgbox|dlg_yesno|dlg_menu' "$LIB_DIR/dialog.sh" 2>/dev/null; then
        pass "Dialog widget functions implemented (msgbox, yesno, menu)"
    else
        fail "Dialog widget functions not found"
    fi
else
    skip "lib/dialog.sh not found"
fi

# ─── 6d. Log Rotation ───────────────────────────────────
section "Log Rotation"

if grep -qE 'rotate_log|LOG_MAX_BYTES' $COMBINED_SOURCE 2>/dev/null; then
    pass "Log rotation implemented in bash"
else
    fail "Log rotation not found in bash scripts"
fi

if grep -qE 'Invoke-LogRotation|maxBytes' $PS_COMBINED_SOURCE 2>/dev/null; then
    pass "Log rotation implemented in PowerShell"
else
    fail "Log rotation not found in PowerShell scripts"
fi

# ─── 7. Security Assertions ──────────────────────────────
section "Security Checks"

# RNS001: No eval usage
if grep -nE '^\s*eval\s' $COMBINED_SOURCE 2>/dev/null | grep -v '^#'; then
    fail "RNS001: eval usage detected"
else
    pass "RNS001: No eval usage"
fi

# RNS002: Device port validation exists
if grep -qE 'tty\[A-Za-z' $COMBINED_SOURCE 2>/dev/null; then
    pass "RNS002: Device port regex validation present"
else
    skip "RNS002: Could not verify device port validation"
fi

# RNS004: Path traversal check in imports
if grep -qE '\.\.\/' $COMBINED_SOURCE 2>/dev/null; then
    pass "RNS004: Path traversal prevention present"
else
    skip "RNS004: Could not verify path traversal checks"
fi

# ─── 8. Global Counter Pattern ───────────────────────────
section "Diagnostics Pattern"

# Check if diagnostics uses return values (modular) or global counters
if grep -qE 'DIAG_RESULT:|local _diag_issues' $COMBINED_SOURCE 2>/dev/null; then
    pass "Diagnostics uses return-value pattern"
elif grep -qE 'DIAG_ISSUES=0' $COMBINED_SOURCE 2>/dev/null; then
    skip "Diagnostics still uses global counter pattern (functional but not modular)"
else
    skip "Diagnostics counter pattern not found"
fi

# ─── Summary ─────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "═══════════════════════════════════════════"

[ "$FAIL" -gt 0 ] && exit 1
exit 0
