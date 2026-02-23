# Security & Code Review — RNS Management Tool

**Initial Review Date:** 2026-02-21 (Session 13)
**Updated:** 2026-02-23 (Session 14 — MeshForge cross-audit + remediation)
**Version Reviewed:** 0.3.5-beta
**Reviewer:** Automated security audit (Claude)
**Scope:** All Bash modules (`lib/*.sh`), PowerShell modules (`pwsh/*.ps1`), dispatchers, config templates, CI, and tests

---

## Executive Summary

The RNS Management Tool demonstrates **production-quality security practices** for a shell-based management tool. All six project security rules (RNS001-RNS006) are properly enforced throughout the codebase. No critical code vulnerabilities were found in the Bash codebase. One moderate security issue was found in PowerShell (curl-pipe-bash in WSL integration). One critical documentation issue was found and fixed (LICENSE file was GPLv3 but docs said MIT — now corrected to GPLv3). Two high-priority code quality issues were identified (RNODE function duplication in Bash, and duplicate Export/Import functions in PowerShell). Nine total recommendations are provided.

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
- Documented exception: meshchat uses `pgrep -f "node.*reticulum-meshchat"` (`lib/utils.sh:339`) — necessary because meshchat runs as a Node.js child process
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

**File:** `lib/utils.sh:339`

The meshchat `pgrep -f` exception is necessary but could be more explicitly documented with a comment explaining that Node.js child processes don't match `-x` pattern.

**Priority:** Cosmetic — existing comment on line 322 provides context, but a line-level comment would aid future reviewers.

### R5: Remove RNODE Function Duplication (High)

**Files:** `lib/install.sh:308-628` and `lib/rnode.sh:9-329`

13 RNODE functions (~320 lines) are byte-for-byte duplicated across both files. Since both files are sourced by the main script, the `install.sh` definitions silently overwrite `rnode.sh` definitions. This is a maintenance hazard — a bug fix in one file won't propagate to the other.

**Recommendation:** Delete the 13 duplicated functions from `lib/install.sh`, keeping `lib/rnode.sh` as the single source of truth. This removes ~320 lines of dead weight and eliminates a class of potential consistency bugs.

**Priority:** High — this is the most impactful code quality improvement available.

### R6: Expand BATS Test Coverage (Medium)

Installation functions (`install_meshchat()`, `install_sideband()`, `install_reticulum_ecosystem()`) and service management functions (`meshtasticd_*()`, `handle_file_transfer()`, `handle_identity_management()`) lack BATS test coverage. Adding ~40-50 tests would cover the most critical untested paths.

**Priority:** Medium — current coverage is strong for validation and hardware safety, but installation/service paths are untested.

### R7: Fix Curl-Pipe-Bash in PowerShell WSL Integration (Moderate)

**Files:** `pwsh/install.ps1:184`, `pwsh/rnode.ps1:305`

Both locations use `curl -fsSL ... | bash -s -- --rnode` to download and execute the management script through WSL. This has two problems: (a) curl-pipe-bash is vulnerable to partial download execution, and (b) the `--rnode` flag does not exist in the bash script — only `--check` is implemented.

**Recommendation:** Either download to a temp file before execution (with checksum), or replace with a WSL command that clones the repo and runs the script properly. Fix or remove the non-existent `--rnode` flag.

**Priority:** Moderate — affects WSL RNODE integration path only, but is a real security and correctness bug.

### R8: Consolidate PowerShell Export/Import Functions (Medium)

**Files:** `pwsh/advanced.ps1:57,109` and `pwsh/backup.ps1:165,210`

Two independent implementations of configuration export/import exist:
- `Export-Configuration` / `Import-Configuration` in advanced.ps1
- `Export-RnsConfiguration` / `Import-RnsConfiguration` in backup.ps1

**Recommendation:** Remove from `pwsh/advanced.ps1` and have the advanced menu call the `pwsh/backup.ps1` versions.

**Priority:** Medium — code quality; two independent implementations may diverge over time.

### R9: Implement `--rnode` Flag or Remove References (Moderate)

**Files:** `pwsh/install.ps1:184`, `pwsh/rnode.ps1:305`, `rns_management_tool.sh`

The PowerShell WSL integration passes `--rnode` to the bash script, but this flag is not handled. The script only recognizes `--check`. This is a **bug** that causes the RNODE WSL fallback to simply launch the full TUI instead of going directly to RNODE configuration.

**Recommendation:** Either implement `--rnode` flag handling in `rns_management_tool.sh` (to jump directly to RNODE config), or remove the flag from the PowerShell WSL calls.

**Priority:** Moderate — functional bug in the Windows-to-WSL RNODE path.

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

*Initial review conducted as part of Session 13. Updated in Session 14 with MeshForge cross-audit and remediation.*

---

## Session 14 Addendum — MeshForge Cross-Audit (2026-02-23)

### Overview

Session 14 pulled recent improvements from [Nursedude/meshforge](https://github.com/Nursedude/meshforge) and performed a cross-audit, applying security patterns and fixes that benefit both projects. Additionally, 3 new security findings were identified and resolved.

### Recommendations Resolved

| Rec | Description | Resolution |
|-----|-------------|------------|
| **R3** | Restrictive `umask` for backup operations | Added `umask 077` around backup and export operations in `lib/backup.sh` |
| **R5** | Remove RNODE function duplication | Removed 13 duplicated functions (~326 lines) from `lib/install.sh`; `lib/rnode.sh` is now single source of truth |
| **R7** | Fix curl-pipe-bash in PowerShell WSL | Replaced pipe-to-bash with download-to-tempfile-then-execute in `pwsh/install.ps1` and `pwsh/rnode.ps1` |
| **R8** | Consolidate PowerShell Export/Import | Replaced duplicate implementations in `pwsh/advanced.ps1` with delegation to canonical versions in `pwsh/backup.ps1` |
| **R9** | Implement `--rnode` flag | Added `--rnode` flag handler in `rns_management_tool.sh` to jump directly to RNODE configuration |

### Recommendations Still Open

| Rec | Description | Priority | Notes |
|-----|-------------|----------|-------|
| **R1** | Checksum for NodeSource script | Minor | Low risk — HTTPS transport security sufficient for most use cases |
| **R2** | Consider `set -u` (nounset) | Minor | Requires extensive testing; codebase uses defensive `${VAR:-}` patterns |
| **R4** | Explicit `pgrep -f` documentation | Cosmetic | Existing comment adequate |
| **R6** | Expand BATS test coverage | Medium | Installation/service paths still untested |

### New Findings — Session 14

#### N1: Hardcoded rnsd Path in Autostart Service (Moderate) — RESOLVED

**File:** `lib/services.sh:679`

The systemd user service file for auto-start hardcoded `ExecStart=/usr/local/bin/rnsd`. When rnsd is installed via `pip install --user` (common on non-root systems), the binary resides at `~/.local/bin/rnsd`, causing silent autostart failure.

**Resolution:** Replaced with `$(command -v rnsd)` to dynamically resolve the actual binary location.

#### N2: Missing Timeout on npm audit (Minor) — RESOLVED

**File:** `lib/install.sh:879`

`npm audit fix` ran without the `run_with_timeout` wrapper, potentially hanging indefinitely on slow or unreachable npm registries.

**Resolution:** Wrapped with `run_with_timeout "$NETWORK_TIMEOUT"`.

#### N3: Log File Permissions (Minor) — RESOLVED

**File:** `lib/core.sh:82`

The management log file (`rns_management.log`) was created with default umask permissions, potentially readable by other users. The log may contain file paths, system information, and operational details.

**Resolution:** Added `chmod 600` on log file creation.

### MeshForge-Sourced Improvements

The following patterns were ported from [meshforge](https://github.com/Nursedude/meshforge):

| Improvement | Source | Applied To |
|-------------|--------|------------|
| RNS domain socket detection (`/proc/net/unix`) | `service_check.py` commit `44007da` | `lib/utils.sh:check_rns_shared_instance()`, `lib/diagnostics.sh` |
| Escape CWD before destructive ops | `scripts/reinstall.sh` commit `f477464` | `lib/advanced.sh` factory reset |
| Download-then-execute (vs curl-pipe-bash) | `install.sh` | `pwsh/install.ps1`, `pwsh/rnode.ps1` |

### Updated Security Rating

**Overall Rating: A** (unchanged)

All 6 security rules (RNS001-RNS006) remain compliant. 5 of 9 original recommendations now resolved. 3 new findings identified and resolved in the same session. No exploitable vulnerabilities found.
