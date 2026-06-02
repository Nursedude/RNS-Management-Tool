# Security & Code Review — RNS Management Tool

**Review Date:** 2026-02-21
**Version Reviewed:** 0.3.5-beta
**Reviewer:** Automated security audit (Claude)
**Scope:** All Bash modules (`lib/*.sh`), PowerShell modules (`pwsh/*.ps1`), dispatchers, config templates, CI, and tests

---

## Executive Summary

The RNS Management Tool demonstrates **production-quality security practices** for a shell-based management tool. All ten project security rules (RNS001-RNS010) are properly enforced throughout the codebase. No critical code vulnerabilities were found in the Bash codebase. One moderate security issue was found in PowerShell (curl-pipe-bash in WSL integration) — **now resolved** (v0.4.0-beta). One critical documentation issue was found and fixed (LICENSE file was GPLv3 but docs said MIT — now corrected to GPLv3). Two high-priority code quality issues were identified (RNODE function duplication in Bash, and duplicate Export/Import functions in PowerShell) — **both now resolved** (v0.4.0-beta). Nine total recommendations were provided; the top 4 (R5, R7, R8, R9) are now resolved.

**Overall Rating: A**

---

## Security Rule Compliance

### RNS001: Array-Based Command Execution — PASS

**Requirement:** Never use `eval`; build commands with arrays.

**Findings:**
- Zero `eval` usage across the entire codebase
- Array-based command construction used consistently for `rnodeconf` calls:
  - `lib/rnode.sh:101` — `declare -a CMD_ARGS=("$device_port")`
  - `lib/rnode.sh:161` — `rnodeconf "${CMD_ARGS[@]}" 2>&1`
- All external command invocations use direct execution, never string interpolation
- `$()` substitution used consistently (no backtick substitution)

### RNS002: Device Port Validation — PASS

**Requirement:** Validate all device port inputs with regex.

**Findings:**
- Strict regex validation: `^/dev/tty[A-Za-z0-9]+$`
  - `lib/rnode.sh:15` — RNODE configuration
  - `lib/install.sh:314` — RNODE firmware installation
- Rejects paths with slashes, dots, or special characters
- Validation occurs before any device interaction

### RNS003: Numeric Range Validation — PASS

**Requirement:** Bounds-check all numeric radio parameters.

**Findings:**
- Spreading Factor: 7-12 (`lib/rnode.sh:130`)
- Coding Rate: 5-8 (`lib/rnode.sh:141`)
- TX Power: -10 to 30 dBm (`lib/rnode.sh:152`)
- All use `^[0-9]+$` regex for type validation before range check
- Invalid values are rejected with warnings, not silently ignored

### RNS004: Path Traversal Prevention — PASS

**Requirement:** Prevent path traversal in import/export operations.

**Findings:**
- Archive import validation (`lib/backup.sh:200-205`):
  ```bash
  if tar -tzf "$IMPORT_FILE" 2>/dev/null | grep -qE '(^/|\.\./)'; then
      print_error "Security: Archive contains invalid paths (absolute or traversal)"
  ```
- Checks for both absolute paths (`^/`) and relative traversal (`../`)
- File extension validation: `[[ ! "$IMPORT_FILE" =~ \.tar\.gz$ ]]` (`lib/backup.sh:194`)
- Content validation: Verifies archive contains expected `.reticulum/`, `.nomadnetwork/`, `.lxmf/` directories
- SUDO_USER validation: Prevents path traversal via username (`lib/core.sh:63-64`)
- `find` operations use `-maxdepth 1` to prevent deep traversal

### RNS005: Destructive Action Confirmation — PASS

**Requirement:** Require explicit confirmation before destructive operations.

**Findings:**
- Factory reset: Requires typing "RESET" to confirm (`lib/advanced.sh:199-202`)
- Factory reset: Creates safety backup before deletion (`lib/advanced.sh:203`)
- Backup deletion: `confirm_action` prompt (`lib/backup.sh:142`)
- Configuration overwrite (import): Warning + confirmation (`lib/backup.sh:221-223`)
- Configuration overwrite (restore): Warning + confirmation (`lib/backup.sh:343-344`)
- RNODE bootloader updates: Confirmation prompt
- System reboot: Confirmation prompt (`rns_management_tool.sh:237`)

### RNS006: Subprocess Timeout Protection — PASS

**Requirement:** Wrap all external operations with timeout protection.

**Findings:**
- `run_with_timeout()` wrapper (`lib/utils.sh:10-19`) with `timeout` command
- Graceful fallback when `timeout` command unavailable
- Timeout constants defined in `lib/core.sh:170-174`:
  - `NETWORK_TIMEOUT=300` (5 min) for network operations
  - `APT_TIMEOUT=600` (10 min) for apt operations
  - `GIT_TIMEOUT=300` (5 min) for git operations
  - `PIP_TIMEOUT=300` (5 min) for pip operations
- `retry_with_backoff()` (`lib/utils.sh:24-46`) with exponential backoff (2s, 4s, 8s...)
- Service polling with bounded waits (`lib/services.sh:23-26`)

### RNS009: Temp Files Must Use mktemp — PASS (Added v0.4.0-beta)

**Requirement:** No hardcoded `/tmp` paths; use `mktemp` or `${TMPDIR:-/tmp}`.

**Findings:**
- Enforced by custom linter rule RNS009 in `scripts/lint.sh`
- All `lib/*.sh` modules pass RNS009 lint check
- WSL commands in PowerShell modules updated to use `${TMPDIR:-/tmp}` pattern

### RNS010: No Sensitive Data in Log Output — PASS (Added v0.4.0-beta)

**Requirement:** Prevent `log_message`/`log_debug`/`log_warn`/`log_error` calls from containing sensitive keywords (password, secret, token, credential, private_key).

**Findings:**
- Enforced by custom linter rule RNS010 in `scripts/lint.sh`
- All `lib/*.sh` modules pass RNS010 lint check
- Protects against accidental plaintext logging of secrets

---

## Additional Security Analysis

### Variable Quoting & Shell Safety

**Rating: Excellent**

- All variables in command arguments are properly double-quoted
- Array expansions use `"${array[@]}"` syntax throughout
- `$SCRIPT_DIR`, `$REAL_HOME`, `$DEVICE_PORT`, `$IMPORT_FILE` — all quoted in every usage
- `set -o pipefail` enabled in main script (`rns_management_tool.sh:18`)
- Script directory resolved safely: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` (`rns_management_tool.sh:21`)

### Service Detection

**Rating: Good**

- Centralized in `check_service_status()` (`lib/utils.sh:317-345`)
- Uses `pgrep -x` (exact match) for all services
- Documented exception: meshchatx uses `pgrep -f "meshchatx"` (`lib/utils.sh`) — necessary because MeshChatX runs as a Python console-script (interpreter) process, not an exec named `meshchatx`, so `-x` would not match
- Comment at `lib/utils.sh:322`: "Never use pgrep -f - it matches editors, grep, and the script itself"
- Prefers `systemctl --user is-active` when available, falls back to pgrep

### Temporary File Handling

**Rating: Good**

- `mktemp -d` for export temp directory (`lib/backup.sh:166`)
- `mktemp` with pattern for downloaded scripts (`lib/install.sh:204`)
- Uses `${TMPDIR:-/tmp}` for WSL2 compatibility
- Cleanup handler removes temp files on exit (`lib/utils.sh:229`)
- Downloaded scripts checked for non-empty before execution: `[ -s "$nodesource_script" ]`

### Signal Handling & Cleanup

**Rating: Good**

- EXIT trap: `cleanup_on_exit` removes temp files, logs exit code (`lib/utils.sh:226-238`)
- INT/TERM trap: User-friendly "Interrupted by user" message, exit 130 (`lib/utils.sh:239`)
- Exit code logging for diagnostic purposes

### Credentials & Secrets

**Rating: Pass**

- No hardcoded passwords, API keys, or tokens in any file
- No `.env` files in repository
- No embedded credentials in config templates
- Git URLs are hardcoded (not user-injectable)

### License Compliance

**Rating: Fixed (was Critical)**

- **Finding:** LICENSE file contained GPLv3 but all documentation (README.md, CLAUDE.md, badges) referenced MIT
- **Resolution:** Updated all documentation to correctly reference GPLv3, matching the LICENSE file
- **Impact:** License mismatch is a legal/compliance issue that could confuse users and downstream projects

### Source File Security

**Rating: Good**

- All `source` directives reference `$SCRIPT_DIR/lib/` — derived from `BASH_SOURCE[0]`
- No sourcing from user-controlled paths
- No dynamic `source` with variable filenames

### `rm -rf` Usage Audit

| Location | Target | Protection |
|----------|--------|-----------|
| `lib/backup.sh:145` | `${backups[$i]}` | Pattern-filtered `.reticulum_backup_*` + `confirm_action` |
| `lib/backup.sh:180` | `$TEMP_EXPORT` | `mktemp -d` created directory |
| `lib/advanced.sh:207-209` | `~/.reticulum`, `~/.nomadnetwork`, `~/.lxmf` | "RESET" confirmation + safety backup |

All `rm -rf` operations target validated paths and are gated behind user confirmation.

### PowerShell Security

**Rating: Good (with one moderate finding)**

- Uses PowerShell cmdlets properly (`Copy-Item`, `Get-ChildItem`, etc.)
- No `Invoke-Expression` (PowerShell equivalent of `eval`)
- No dynamic code execution in normal paths
- `.PSScriptAnalyzerSettings.psd1` configured for linting in CI

**MODERATE: Curl-pipe-bash in WSL integration**

Two locations pipe a remote script directly to bash:
- `pwsh/install.ps1:184` — `wsl ... bash -c "curl -fsSL https://raw.githubusercontent.com/.../rns_management_tool.sh | bash -s -- --rnode"`
- `pwsh/rnode.ps1:305` — identical pattern

Issues:
1. Classic curl-pipe-bash anti-pattern — partial download could execute truncated script
2. The `--rnode` flag does not exist in `rns_management_tool.sh` (only `--check` is implemented) — this is a **bug**
3. No checksum or signature verification

**Duplicate Export/Import functions:**
- `pwsh/advanced.ps1:57` defines `Export-Configuration` / `Import-Configuration`
- `pwsh/backup.ps1:165` defines `Export-RnsConfiguration` / `Import-RnsConfiguration`
- Two independent implementations of the same functionality with different function names

---

## Code Quality Assessment

### Architecture

- **Modular design**: 10 Bash modules + 9 PowerShell modules, sourced in dependency order
- **Single dispatcher**: Main script is 326 lines, purely menu routing
- **Separation of concerns**: Each module handles one domain (backup, services, diagnostics, etc.)

### Code Duplication — HIGH

**Finding:** 13 RNODE functions (~320 lines) are byte-for-byte identical in both `lib/install.sh:308-628` and `lib/rnode.sh:9-329`.

Duplicated functions: `rnode_get_device_port()`, `rnode_autoinstall()`, `rnode_list_devices()`, `rnode_flash_device()`, `rnode_update_device()`, `rnode_get_info()`, `rnode_configure_radio()`, `rnode_set_model()`, `rnode_eeprom()`, `rnode_bootloader()`, `rnode_serial_console()`, `rnode_show_help()`, `configure_rnode_interactive()`.

**Impact:** Bug fixes in one file won't propagate to the other. Adds ~320 lines (~6%) of unnecessary bloat. Since `lib/rnode.sh` is sourced before `lib/install.sh` in the main script (line 40 vs 37), the `install.sh` definitions silently overwrite the `rnode.sh` ones.

**Recommendation:** Remove the 13 duplicated RNODE functions from `lib/install.sh`, keeping `lib/rnode.sh` as the single source of truth.

### Function Design

- All functions under the 200-line project limit
- Consistent naming: `print_*`, `show_*`, `check_*`, `install_*`, `get_*`
- Single responsibility per function
- Input validation at function entry points
- Minor naming inconsistency: `rnode_*` prefix used in rnode module vs `install_*`/`check_*` pattern elsewhere

### Error Handling

- `safe_call()` wrapper with exit code categorization: 126 (permission), 127 (not found), 124 (timeout), 130 (interrupt) (`lib/utils.sh:457-489`)
- `show_error_help()` provides context-specific troubleshooting (`lib/utils.sh:242-311`)
- Leveled logging: DEBUG, INFO, WARN, ERROR (`lib/utils.sh:207-222`)
- Log rotation: 1MB threshold, 3 rotated copies (`lib/core.sh:99-128`)

### Performance

- Status caching with 10-second TTL avoids repeated `pgrep`/`pip3` calls (`lib/utils.sh:491-566`)
- One-time tool detection at startup (`lib/utils.sh:109-139`)
- Bounded polling loops instead of fixed sleeps

### Static Analysis

- ShellCheck: Zero warnings (enforced in CI)
- PSScriptAnalyzer: Configured in CI workflow
- Bash syntax checks: All files pass `bash -n`

### Test Coverage

| Suite | Assertions | Scope |
|-------|-----------|-------|
| `tests/smoke_test.sh` | 183 | Function definitions, syntax, module loading |
| `tests/rns_management_tool.bats` | 63 | Core functionality, menus, validation |
| `tests/hardware_validation.bats` | 92 | RNODE hardware safety across 21+ boards |
| `tests/integration_tests.bats` | 106 | Service polling, backup round-trip, platform detection |
| Pester tests (9 files) | 343 | PowerShell modules (rnode 57, services 61, backup 48, core 37, install 36, diagnostics 33, ui 27, advanced 23, environment 21) |
| **Total** | **787+** | |

All 9 PowerShell modules now have Pester test coverage.

---

## Recommendations

### R1: Checksum Verification for Downloaded Scripts (Minor)

**File:** `lib/install.sh:204-207`

The NodeSource setup script is downloaded and executed. While the download uses HTTPS and the file is checked for non-empty (`[ -s ]`), adding SHA256 checksum verification would strengthen supply-chain security.

**Current:**
```bash
curl -fsSL -o "$nodesource_script" https://deb.nodesource.com/setup_22.x
[ -s "$nodesource_script" ] && sudo -E bash "$nodesource_script"
```

**Suggested enhancement:**
```bash
# Verify known-good checksum before execution
local expected_sha256="<known-hash>"
local actual_sha256=$(sha256sum "$nodesource_script" | awk '{print $1}')
if [ "$actual_sha256" != "$expected_sha256" ]; then
    print_error "Checksum mismatch for NodeSource setup script"
    return 1
fi
```

**Priority:** Low — HTTPS provides transport security, and NodeSource is a trusted source. However, checksum verification protects against compromised CDN or MITM scenarios.

### R2: Consider `set -u` (nounset) (Minor)

**File:** `rns_management_tool.sh:18`

Currently only `set -o pipefail` is enabled. Adding `set -u` would catch uninitialized variable bugs at runtime. This requires auditing all `${VAR:-default}` patterns to ensure compatibility.

**Priority:** Low — the codebase already uses defensive `${VAR:-}` patterns extensively. Would add an extra safety net but requires careful testing.

### R3: Restrictive `umask` for Backup Operations (Minor)

**File:** `lib/backup.sh`

Backup and export operations create files with the default umask. Setting `umask 077` before creating backups would ensure only the owner can read them, protecting sensitive identity keys and configuration.

**Priority:** Low — backups are stored in the user's home directory which is typically restricted. Adds defense-in-depth for shared systems.

### R4: Explicit `pgrep -f` Documentation (Cosmetic)

**File:** `lib/utils.sh`

The meshchatx `pgrep -f` exception is necessary but could be more explicitly documented with a comment explaining that the Python console-script process doesn't match the `-x` pattern.

**Priority:** Cosmetic — existing comment on line 322 provides context, but a line-level comment would aid future reviewers.

### R5: Remove RNODE Function Duplication (High) — RESOLVED

**Files:** `lib/install.sh:308-628` and `lib/rnode.sh:9-329`

13 RNODE functions (~320 lines) were byte-for-byte duplicated across both files. Since both files are sourced by the main script, the `install.sh` definitions silently overwrite `rnode.sh` definitions.

**Resolution:** Duplicated functions removed from `lib/install.sh`. `lib/rnode.sh` is now the single source of truth. Resolved in v0.4.0-beta (Session 14).

### R6: Expand BATS Test Coverage (Medium)

Installation functions (`install_meshchat()`, `install_sideband()`, `install_reticulum_ecosystem()`) and service management functions (`meshtasticd_*()`, `handle_file_transfer()`, `handle_identity_management()`) lack BATS test coverage. Adding ~40-50 tests would cover the most critical untested paths.

**Priority:** Medium — current coverage is strong for validation and hardware safety, but installation/service paths are untested.

### R7: Fix Curl-Pipe-Bash in PowerShell WSL Integration (Moderate) — RESOLVED

**Files:** `pwsh/install.ps1:184`, `pwsh/rnode.ps1:305`

Both locations used `curl -fsSL ... | bash -s -- --rnode` to download and execute the management script through WSL.

**Resolution:** Downloads now use temp file with `mktemp ${TMPDIR:-/tmp}` pattern. The `--rnode` flag was implemented in `rns_management_tool.sh`. Resolved in v0.4.0-beta (Sessions 14-15).

### R8: Consolidate PowerShell Export/Import Functions (Medium) — RESOLVED

**Files:** `pwsh/advanced.ps1:57,109` and `pwsh/backup.ps1:165,210`

Two independent implementations of configuration export/import existed.

**Resolution:** Duplicate functions removed from `pwsh/advanced.ps1`. Advanced menu now calls `pwsh/backup.ps1` versions. Resolved in v0.4.0-beta (Session 14).

### R9: Implement `--rnode` Flag or Remove References (Moderate) — RESOLVED

**Files:** `pwsh/install.ps1:184`, `pwsh/rnode.ps1:305`, `rns_management_tool.sh`

The PowerShell WSL integration passed `--rnode` to the bash script, but this flag was not handled.

**Resolution:** `--rnode` flag implemented in `rns_management_tool.sh` to jump directly to RNODE configuration. Resolved in v0.4.0-beta (Session 14).

---

## Files Reviewed

### Bash (19 files)
- `rns_management_tool.sh` (326 lines)
- `lib/core.sh`, `lib/utils.sh`, `lib/ui.sh`, `lib/install.sh`, `lib/rnode.sh`
- `lib/services.sh`, `lib/backup.sh`, `lib/diagnostics.sh`, `lib/config.sh`, `lib/advanced.sh`
- `config_templates/minimal.conf`, `lora_rnode.conf`, `tcp_client.conf`, `transport_node.conf`
- `tests/smoke_test.sh`, `tests/rns_management_tool.bats`, `tests/hardware_validation.bats`, `tests/integration_tests.bats`

### PowerShell (11 files)
- `rns_management_tool.ps1` (144 lines)
- `pwsh/core.ps1`, `pwsh/ui.ps1`, `pwsh/environment.ps1`, `pwsh/install.ps1`, `pwsh/rnode.ps1`
- `pwsh/services.ps1`, `pwsh/backup.ps1`, `pwsh/diagnostics.ps1`, `pwsh/advanced.ps1`

### CI/Config (2 files)
- `.github/workflows/lint.yml`
- `.PSScriptAnalyzerSettings.psd1`

### Documentation (5 files)
- `README.md`, `CLAUDE.md`, `QUICKSTART.md`, `CHANGELOG.md`, `SESSION_NOTES.md`

---

## Conclusion

The RNS Management Tool has a strong security foundation with well-implemented defenses against common shell scripting vulnerabilities. The project's security rules (RNS001-RNS006) are effectively enforced and the codebase reflects disciplined security practices. The most actionable finding is R5 (RNODE function duplication) — a straightforward cleanup that removes ~320 lines of redundant code. The four minor recommendations are defense-in-depth improvements. No exploitable vulnerabilities were found.

---

*Review conducted as part of Session 13 — see SESSION_NOTES.md for development history.*
