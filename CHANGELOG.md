# Changelog

All notable changes to the RNS Management Tool will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.5-beta] - 2026-02-15

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
