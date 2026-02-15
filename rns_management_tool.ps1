<#
.SYNOPSIS
    RNS Management Tool for Windows - Part of the MeshForge Ecosystem
.DESCRIPTION
    Complete Reticulum Network Stack Management Solution for Windows 11
    Supports native Windows and WSL2 installations

    This is the only MeshForge ecosystem tool with native Windows support.
    Upstream meshforge updates are frequent - check for updates regularly.
.NOTES
    Version: 0.3.5-beta
    Requires: PowerShell 5.1+ or PowerShell Core 7+
    Run as Administrator for best results
    MeshForge: https://github.com/Nursedude/meshforge
#>

#Requires -Version 5.1

# Resolve script directory reliably (meshforge pattern)
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Script configuration
$Script:Version = "0.3.5-beta"
# Note: $env:USERPROFILE is the correct home on Windows (no sudo/REAL_HOME issue)
$Script:RealHome = $env:USERPROFILE
$Script:LogFile = Join-Path $Script:RealHome "rns_management.log"
$Script:BackupDir = Join-Path $Script:RealHome ".reticulum_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$Script:NeedsReboot = $false

# Environment detection flags (adapted from meshforge launcher.py)
$Script:IsAdmin = $false
$Script:HasWSL = $false
$Script:HasColor = $true
$Script:IsRemoteSession = $false

# Network Timeout Constants (RNS006: Subprocess timeout protection)
$Script:NetworkTimeout = 300    # 5 minutes for network operations
$Script:PipTimeout = 300        # 5 minutes for pip operations

# Log levels (adapted from meshforge logging_config.py)
$Script:LogLevelDebug = 0
$Script:LogLevelInfo = 1
$Script:LogLevelWarn = 2
$Script:LogLevelError = 3
$Script:CurrentLogLevel = $Script:LogLevelInfo

#########################################################
# Source Modules (dependency order)
#########################################################

# Core: environment detection, logging, health checks
. "$Script:ScriptDir\pwsh\core.ps1"

# UI: color output, headers, menus
. "$Script:ScriptDir\pwsh\ui.ps1"

# Environment: WSL, Python, pip detection
. "$Script:ScriptDir\pwsh\environment.ps1"

# Installation: Python, Reticulum, MeshChat, Sideband
. "$Script:ScriptDir\pwsh\install.ps1"

# RNODE: device configuration and management
. "$Script:ScriptDir\pwsh\rnode.ps1"

# Services: start/stop, autostart, network tools
. "$Script:ScriptDir\pwsh\services.ps1"

# Backup: backup/restore, export/import
. "$Script:ScriptDir\pwsh\backup.ps1"

# Diagnostics: 6-step system checks
. "$Script:ScriptDir\pwsh\diagnostics.ps1"

# Advanced: config management, updates, factory reset
. "$Script:ScriptDir\pwsh\advanced.ps1"

#########################################################
# Main Entry Function
#########################################################

function Main {
    # Initialize environment detection (meshforge pattern)
    Initialize-Environment

    # Rotate log if needed (meshforge 1MB rotation pattern)
    Invoke-LogRotation

    # Initialize log
    Write-RnsLog "=== RNS Management Tool for Windows Started ===" "INFO"
    Write-RnsLog "Version: $($Script:Version)" "INFO"
    Write-RnsLog "RealHome=$($Script:RealHome), ScriptDir=$($Script:ScriptDir)" "INFO"

    # Run startup health check (meshforge startup_health.py pattern)
    Invoke-StartupHealthCheck

    # Main loop
    while ($true) {
        $choice = Show-MainMenu

        switch ($choice) {
            "1" { Install-Reticulum -UseWSL $false }
            "2" { Install-Reticulum -UseWSL $true }
            "3" { Show-RnodeMenu }
            "4" { Install-Sideband }
            "5" { Install-NomadNet }
            "m" { Install-MeshChat }
            "M" { Install-MeshChat }
            "6" { Show-Diagnostic }
            "7" { Show-ServiceMenu }
            "8" { Show-BackupMenu }
            "9" { Show-AdvancedMenu }
            "0" {
                Write-Host ""
                Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
                Write-Host "│  Thank you for using RNS Management Tool!              │" -ForegroundColor Cyan
                Write-Host "│  Part of the MeshForge Ecosystem                       │" -ForegroundColor Cyan
                Write-Host "│  github.com/Nursedude/RNS-Management-Tool              │" -ForegroundColor Cyan
                Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
                Write-Host ""
                Write-RnsLog "=== RNS Management Tool Ended ===" "INFO"
                exit 0
            }
            default {
                Write-ColorOutput "Invalid option" "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Check if running on Windows
# PowerShell 5.1 and below are Windows-only ($IsWindows doesn't exist).
# PowerShell 6+ defines $IsWindows as a readonly automatic variable.
$isRunningOnWindows = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }

if (-not $isRunningOnWindows) {
    Write-Host "Error: This script is designed for Windows systems" -ForegroundColor Red
    Write-Host "For Linux/Mac, please use rns_management_tool.sh" -ForegroundColor Yellow
    exit 1
}

# Run main program
Main
