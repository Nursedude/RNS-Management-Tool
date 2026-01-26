# Changelog

All notable changes to the RNS Management Tool will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0-beta] - 2026-01-26

### Changed
- **Version Reset**: Moved to semantic versioning starting at 0.x to reflect beta status
- Previous v2.2.0 functionality preserved, version number adjusted for honesty

### Added
- **Subprocess Timeouts**: Network operations now have explicit timeouts (300s default)
- **Archive Validation**: Import function validates tar structure before extraction
- **Function Decomposition**: Long functions split into smaller, testable units
- **Bats Test Suite**: Basic shell testing framework for CI validation
- **MeshForge Compliance**: 100% compliance with MeshForge domain principles

### Security
- RNS001: Array-based command execution (enforced)
- RNS002: Device port validation with regex (enforced)
- RNS003: Numeric range validation (enforced)
- RNS004: Path traversal prevention (enforced)
- RNS005: Destructive action confirmation (enforced)
- RNS006: Subprocess timeout protection (NEW)

### Documentation
- Added CLAUDE.md development guide
- Added CODE_REVIEW_MESHFORGE.md with domain analysis
- Updated README.md with mermaid architecture diagrams

---

## [2.2.0] - 2025-12-30 (Legacy Version Number)

### Added (PowerShell/Windows)
- **Advanced Options Menu** with comprehensive system management
  - Update Python packages functionality
  - Reinstall all components option
  - Clean cache and temporary files
  - Export configuration to portable .zip archives
  - Import configuration from .zip archives
  - Factory reset with safety backup
  - View logs directly from menu
  - Check for tool updates from GitHub
- **Service Management Submenu** for better rnsd control
  - Start rnsd daemon
  - Stop rnsd daemon
  - Restart rnsd daemon
  - View detailed service status
- **Update Checker** - Automatically check GitHub for new releases
- **Enhanced Diagnostics** - More comprehensive system information

### Added (Both Scripts)
- **Code Review Report** - Comprehensive code quality analysis document
- **Better Error Context** - More actionable recovery suggestions

### Changed (PowerShell/Windows)
- Reorganized main menu for better clarity
- Menu option 7 now opens Service Management submenu
- Menu option 8 for Backup/Restore (was 9)
- Menu option 9 now opens Advanced Options
- Improved visual consistency in status displays
- Better alignment of Quick Status Dashboard

### Changed (Bash/Linux)
- Version number updated to 2.2.0 for consistency

### Improved
- **UI/UX Polish**
  - Consistent navigation patterns across both scripts
  - Better menu organization and categorization
  - Improved box drawing and alignment
  - Clearer option descriptions

- **Code Quality**
  - Added comprehensive inline documentation
  - Better function organization
  - Improved error handling patterns
  - More consistent naming conventions

### Fixed
- Visual alignment issues in PowerShell Quick Status Dashboard
- Menu numbering consistency across platforms
- Various edge cases in configuration management

### Security
- Enhanced input validation in configuration import
- Path validation for export/import operations
- Secure temporary file handling in archive operations

## [2.1.0] - 2024-12-XX

### Added (Bash/Linux)
- Quick Status Dashboard on main menu
- Organized menu sections (Installation, Management, System)
- Export/Import configuration (.tar.gz archives)
- Factory Reset functionality with safety backup

### Added (PowerShell/Windows)
- NomadNet installation support
- Basic diagnostics functionality
- Improved WSL integration

### Security
- Replaced unsafe `eval` with array-based command execution
- Device port validation (`^/dev/tty[A-Za-z0-9]+$`)
- Radio parameter input validation
  - Frequency: numeric validation
  - Bandwidth: numeric validation
  - Spreading Factor: range 7-12
  - Coding Rate: range 5-8
  - TX Power: range -10 to 30 dBm

### Fixed
- Portability issues with `grep -oP` (replaced with `sed`)
- Command injection vulnerabilities

## [2.0.0] - 2024-XX-XX

### Added
- Complete UI overhaul with interactive menus
- Windows 11 support with PowerShell installer
- WSL detection and integration
- Interactive RNODE installer and configuration wizard
- Enhanced Raspberry Pi detection (all models)
- Comprehensive diagnostics system
- Improved backup/restore functionality
- Better error handling and recovery
- Progress indicators and visual feedback
- Automated environment detection
- Service management improvements

### Changed
- Complete rewrite of menu system
- Modernized user interface with colors
- Improved error messages
- Better logging system

## [1.0.0] - 2024-XX-XX

### Added
- Initial release
- Basic update functionality
- Raspberry Pi support
- Simple command-line interface
- Core RNS installation
- LXMF support
- NomadNet installation

---

## Version Comparison

| Feature | v1.0.0 | v2.0.0 | v2.1.0 | v2.2.0 |
|---------|--------|--------|--------|--------|
| Interactive Menu | ❌ | ✅ | ✅ | ✅ |
| Windows Support | ❌ | ✅ | ✅ | ✅ |
| Quick Status | ❌ | ❌ | ✅ | ✅ |
| Security Hardening | ⚠️ | ⚠️ | ✅ | ✅ |
| Export/Import Config (Linux) | ❌ | ❌ | ✅ | ✅ |
| Export/Import Config (Windows) | ❌ | ❌ | ❌ | ✅ |
| Advanced Options (Linux) | ❌ | ⚠️ | ✅ | ✅ |
| Advanced Options (Windows) | ❌ | ❌ | ❌ | ✅ |
| Factory Reset (Linux) | ❌ | ❌ | ✅ | ✅ |
| Factory Reset (Windows) | ❌ | ❌ | ❌ | ✅ |
| Update Checker | ❌ | ❌ | ❌ | ✅ |
| Code Review Docs | ❌ | ❌ | ❌ | ✅ |

## Upgrade Notes

### Upgrading to 2.2.0

- No breaking changes from 2.1.0
- Windows users will see new Advanced Options menu (option 9)
- Service management moved to dedicated submenu (option 7)
- All existing configurations remain compatible
- Backup/Restore moved from option 9 to option 8 (Windows only)

### Upgrading to 2.1.0

- No breaking changes from 2.0.0
- New security features automatically applied
- Existing configurations remain compatible
- Recommended: Create backup before upgrading

### Upgrading from 1.x to 2.x

- Major UI changes - completely new menu system
- All data preserved during upgrade
- Recommended: Create manual backup of `~/.reticulum` before upgrading
- New features available immediately after upgrade

## Links

- [GitHub Repository](https://github.com/Nursedude/RNS-Management-Tool)
- [Latest Release](https://github.com/Nursedude/RNS-Management-Tool/releases/latest)
- [Report Issues](https://github.com/Nursedude/RNS-Management-Tool/issues)
- [Reticulum Network](https://reticulum.network/)
