# Changelog

All notable changes to the RNS Management Tool will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Windows keep-alive (Phase 1B)**: the Services menu now registers logon-triggered
  Scheduled Tasks with **restart-on-failure** (up to 3×/min) for `rnsd` and MeshChatX —
  a Windows-native watchdog (no admin, runs in the user session). New menu entries for
  enabling/disabling each and an auto-start status view; Enable offers to start the task
  immediately so it can be tested without logging off. `Stop rnsd` now warns when
  keep-alive is active (it will restart the daemon). New functions:
  `Enable-MeshChatXAutoStart`, `Disable-MeshChatXAutoStart`, `Get-RnsAutoStartStatus`;
  `Enable-RnsdAutoStart` upgraded with the watchdog settings.
- **RNS environment doctor** (diagnostics): new step in both the bash (now 8-step)
  and PowerShell (now 7-step) diagnostics. Detects the version/ownership/PATH
  gotchas a naive `pip show rns` misses — *which* RNS `python` actually imports and
  from where, **pip-reported vs imported version mismatch** (shadowed installs),
  `rnsd`/`meshchatx` not being on PATH, and (Linux) `~/.reticulum` owned by the
  wrong user from a `sudo pip`. On Windows it also flags the Microsoft Store
  `python` alias-stub trap and multiple-interpreter confusion.

### Changed
- **MeshChat → MeshChatX migration**: Menu option 4 now installs MeshChatX
  (`reticulum-meshchatx`) from PyPI instead of the deprecated
  `liamcottle/reticulum-meshchat`. The pip wheel bundles the built frontend, so
  the installer no longer requires Node.js, npm, a git clone, or a build step on
  either Linux or Windows — a much lighter, cross-platform path.
- Service detection now matches the `meshchatx` Python daemon (web UI on
  `https://127.0.0.1:8000`) instead of the old Node.js process.

### Added
- **MeshChatX service control**: Start/Stop entries in the Services menu and an
  optional `systemd --user` auto-start unit (written atomically) on login.
- **RNS version-parity advisory**: `ensure_rns_floor()` logs a warning if the
  installed RNS is below MeshChatX's `rns>=1.2.5` requirement (pip resolves it).
- **Python 3.11+ gate**: the MeshChatX installer fails fast with a clear message
  on older Python instead of an opaque pip `requires-python` error.

### Removed
- Node.js / npm dependency and the MeshChat build-log viewer (no build step).
- Legacy git-based MeshChat install is detected and offered for removal to
  reclaim disk space.

## [0.4.0-beta] - 2026-03-04

### Added
- **Granular Service Health States**: 6 states (running, degraded, starting, zombie, stopped, unreachable) with process + port + uptime classification
- **Deployment Profiles**: 3 role-based profiles (Relay Node, Mobile Station, Base Station) for one-click configuration
- **Enhanced Diagnostics**: CPU load checks, thermal monitoring (70C warn / 80C error), config section validation, return codes for scripted use
- **RNS009 Linter Rule**: Enforces `mktemp` usage instead of hardcoded `/tmp` paths
- **RNS010 Linter Rule**: Prevents sensitive data (passwords, tokens, keys) in log output
- **Dead Code Detection**: `scripts/dead_code_check.sh` development tool for finding unused functions
- **Service Health Tests**: 24 new BATS tests for granular health state classification
- **Diagnostics Enhanced Tests**: 15 new BATS tests for diagnostic engine improvements
- **Regression Guard Tests**: 5 new tests for RNS009/RNS010 compliance
- **Integration Tests**: 8 new tests for config management and service workflows

### Changed
- `check_service_status()` now sets `_LAST_SERVICE_STATE` as side effect for granular state access
- Cache functions store granular state strings instead of simple "running"/"stopped"
- Main menu and service display use case-based rendering for all 6 health states
- `run_diagnostics()` returns 0 (healthy), 1 (warnings), or 2 (issues) for scripted use
- Custom linter expanded from RNS001-RNS008 to RNS001-RNS010
- CI workflow runs 3 additional BATS test suites
- Version bumped to 0.4.0-beta

### Fixed
- WSL commands in `pwsh/install.ps1` and `pwsh/rnode.ps1` now use `${TMPDIR:-/tmp}` instead of hardcoded `/tmp`

### Security
- RNS009: Temp file safety — no hardcoded `/tmp` paths in production code
- RNS010: Log output safety — no sensitive data keywords in log function calls
- All P1 issues from Security Review now resolved (R5 RNODE dedup, R7/R9 curl-pipe-bash, R8 PS dedup)

## [0.3.5-beta] - 2026-02-15

### Security
- Formal security and code review completed — all RNS001-RNS006 rules verified PASS
- Created `SECURITY_REVIEW.md` documenting audit findings, line-number references, and recommendations
- Audited all `rm -rf` usage, `pgrep` patterns, temp file handling, signal traps, variable quoting
- Overall security rating: A — no critical vulnerabilities found
- 9 recommendations: RNODE dedup (high), curl-pipe-bash (moderate), PS dedup (medium), BATS expansion (medium), 4 minor defense-in-depth, `--rnode` bug
- **Found**: 13 RNODE functions (~320 lines) duplicated between `lib/install.sh` and `lib/rnode.sh`
- **Found**: curl-pipe-bash in PowerShell WSL integration with non-existent `--rnode` flag
- **Found**: Duplicate Export/Import functions in `pwsh/advanced.ps1` vs `pwsh/backup.ps1`

### Documentation
- Added `SECURITY_REVIEW.md` — comprehensive security and code review document
- Updated `SESSION_NOTES.md` with Session 13 review findings
- **Fixed LICENSE mismatch**: All docs now correctly reference GPLv3 (matching LICENSE file)
- **Fixed test counts**: Corrected BATS and Pester counts (Pester: 343 across 9 files, was 118+ across 8)

### Added
- **Log Rotation**: Automatic 1MB rotation for UPDATE_LOG with 3 rotated copies; cleanup of legacy per-session timestamped logs — both Bash and PowerShell
- **PowerShell Modularization**: Split 2,727-line monolithic ps1 into 9 modules under `pwsh/` (core, ui, environment, install, rnode, services, backup, diagnostics, advanced)
- **Bash Modularization**: Split 4,514-line monolithic bash script into 10 modules under `lib/` (core, utils, ui, install, rnode, services, backup, diagnostics, config, advanced)
- **CI Smoke Test Job**: New `smoke-test` and `check-mode` jobs in GitHub Actions workflow
- **CI Module Validation**: ShellCheck and syntax checks now cover `lib/*.sh` and `pwsh/*.ps1` modules
- **Hardware Validation Tests**: 104 tests covering RNODE hardware safety across 21+ boards
- **Integration Tests**: 107 tests covering service polling, backup round-trip, platform detection
- **Pester Tests**: 118+ tests for PowerShell modules (rnode, backup)
- **CI Pester Job**: Pester v5 on `windows-latest` runner

### Changed
- PowerShell log path now uses stable `rns_management.log` instead of per-session timestamped files
- Bash UPDATE_LOG now uses stable path with rotation instead of accumulating session files
- CI workflow expanded from 3 to 6 jobs (shellcheck, check-mode, smoke-test, bats, powershell, pester)
- Version bumped to 0.3.5-beta

### Fixed
- `safe_call()` exit code capture bug — was capturing `if` test result, not command exit code
- Hardcoded `/tmp` paths — now uses `${TMPDIR:-/tmp}` for WSL2 compatibility

## [0.3.0-beta] - 2026-01-26

### Changed
- **Version Reset**: Moved to semantic versioning starting at 0.x to reflect beta status
- Previous v2.2.0 functionality preserved, version number adjusted for honesty

### Added
- **Subprocess Timeouts**: Network operations now have explicit timeouts (300s default)
- **Archive Validation**: Import function validates tar structure before extraction
- **Function Decomposition**: Long functions split into smaller, testable units
- **Bats Test Suite**: Basic shell testing framework for CI validation
- **Config Templates**: 4 pre-built RNS configurations (minimal, LoRa RNODE, TCP client, transport node)
- **First-Run Wizard**: Guides new users through install, config, and daemon start
- **Capability Detection**: Scans 8 RNS tools + 5 dependencies at startup
- **Enhanced Diagnostics**: 6-step actionable diagnostic with "Fix:" suggestions
- **RNS Utility Integration**: rncp (file transfer), rnx (remote command), rnid (identity management)
- **Emergency Quick Mode**: Simplified field operations menu
- **ANSI Clear Screen**: Eliminates TUI flash on screen redraw
- **Compact Status Line**: Shows version, rnsd status, tool count, SSH indicator in header
- **rnsd Uptime Display**: Tracks daemon uptime with human-readable format
- **PowerShell Service Menu**: File transfer, remote command, auto-start (Task Scheduler)
- **PowerShell Backup Menu**: Export/import .zip, backup listing, old backup pruning

### Security
- RNS001: Array-based command execution (enforced)
- RNS002: Device port validation with regex (enforced)
- RNS003: Numeric range validation (enforced)
- RNS004: Path traversal prevention (enforced)
- RNS005: Destructive action confirmation (enforced)
- RNS006: Subprocess timeout protection (enforced)

### Documentation
- Added CLAUDE.md development guide
- Updated README.md with mermaid architecture diagrams

---

## [2.2.0] - 2025-12-30 (Legacy)

### Added
- PowerShell Advanced Options menu (update packages, reinstall, clean cache, export/import, factory reset, logs, update checker)
- PowerShell Service Management submenu (start/stop/restart/status)
- Code quality improvements and inline documentation

### Changed
- Reorganized Windows main menu for better clarity
- Improved visual consistency in status displays

## [2.1.0] - 2024-12

### Added
- Quick Status Dashboard on main menu
- Export/Import configuration (.tar.gz archives)
- Factory Reset functionality with safety backup

### Security
- Replaced unsafe `eval` with array-based command execution
- Device port and radio parameter input validation

## [2.0.0] - 2024

### Added
- Complete UI overhaul with interactive menus
- Windows 11 support with PowerShell installer
- WSL detection and integration
- Interactive RNODE installer and configuration wizard

## [1.0.0] - 2024

### Added
- Initial release with basic update functionality and Raspberry Pi support

---

## Links

- [GitHub Repository](https://github.com/Nursedude/RNS-Management-Tool)
- [Latest Release](https://github.com/Nursedude/RNS-Management-Tool/releases/latest)
- [Report Issues](https://github.com/Nursedude/RNS-Management-Tool/issues)
- [Reticulum Network](https://reticulum.network/)
