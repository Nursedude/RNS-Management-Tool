<#
.SYNOPSIS
    RNS Management Tool for Windows 11
.DESCRIPTION
    Complete Reticulum Network Stack Management Solution for Windows 11
    Supports native Windows and WSL2 installations
.NOTES
    Version: 2.0.0
    Requires: PowerShell 5.1+ or PowerShell Core 7+
    Run as Administrator for best results
#>

#Requires -Version 5.1

# Script configuration
$Script:Version = "2.0.0"
$Script:LogFile = Join-Path $env:USERPROFILE "rns_management_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Script:BackupDir = Join-Path $env:USERPROFILE ".reticulum_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$Script:NeedsReboot = $false

#########################################################
# Color and Display Functions
#########################################################

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Type - $Message" | Out-File -FilePath $Script:LogFile -Append

    switch ($Type) {
        "Success" {
            Write-Host "[✓] " -ForegroundColor Green -NoNewline
            Write-Host $Message
        }
        "Error" {
            Write-Host "[✗] " -ForegroundColor Red -NoNewline
            Write-Host $Message
        }
        "Warning" {
            Write-Host "[!] " -ForegroundColor Yellow -NoNewline
            Write-Host $Message
        }
        "Info" {
            Write-Host "[i] " -ForegroundColor Cyan -NoNewline
            Write-Host $Message
        }
        "Progress" {
            Write-Host "[►] " -ForegroundColor Magenta -NoNewline
            Write-Host $Message
        }
        default {
            Write-Host $Message
        }
    }
}

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                        ║" -ForegroundColor Cyan
    Write-Host "║           RNS MANAGEMENT TOOL v$($Script:Version)                ║" -ForegroundColor Cyan
    Write-Host "║     Complete Reticulum Network Stack Manager           ║" -ForegroundColor Cyan
    Write-Host "║                  Windows 11 Edition                    ║" -ForegroundColor Cyan
    Write-Host "║                                                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Detect environment
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    Write-Host "Platform:      " -NoNewline
    Write-Host "Windows $([Environment]::OSVersion.Version.Major).$([Environment]::OSVersion.Version.Minor)" -ForegroundColor Green

    Write-Host "Architecture:  " -NoNewline
    Write-Host "$env:PROCESSOR_ARCHITECTURE" -ForegroundColor Green

    Write-Host "Admin Rights:  " -NoNewline
    if ($isAdmin) {
        Write-Host "Yes" -ForegroundColor Green
    } else {
        Write-Host "No (some features may be limited)" -ForegroundColor Yellow
    }

    # Check for WSL
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        Write-Host "WSL:           " -NoNewline
        Write-Host "Available" -ForegroundColor Green
    }

    Write-Host ""
}

function Show-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "▶ $Title" -ForegroundColor Blue
    Write-Host ""
}

function Show-Progress {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity
    )

    $percent = [math]::Round(($Current / $Total) * 100)
    Write-Progress -Activity $Activity -PercentComplete $percent -Status "$percent% Complete"
}

#########################################################
# Environment Detection
#########################################################

function Test-WSL {
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        try {
            $wslOutput = wsl --list --quiet 2>$null
            if ($wslOutput) {
                return $true
            }
        } catch {
            return $false
        }
    }
    return $false
}

function Get-WSLDistributions {
    if (-not (Test-WSL)) {
        return @()
    }

    try {
        $distros = wsl --list --quiet | Where-Object { $_ -and $_.Trim() }
        return $distros
    } catch {
        return @()
    }
}

function Test-Python {
    Show-Section "Checking Python Installation"

    # Check for Python in PATH
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        $python = Get-Command python3 -ErrorAction SilentlyContinue
    }

    if ($python) {
        $version = & $python.Source --version 2>&1
        Write-ColorOutput "Python detected: $version" "Success"
        return $true
    } else {
        Write-ColorOutput "Python not found in PATH" "Error"
        return $false
    }
}

function Test-Pip {
    $pip = Get-Command pip -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = Get-Command pip3 -ErrorAction SilentlyContinue
    }

    if ($pip) {
        $version = & $pip.Source --version 2>&1
        Write-ColorOutput "pip detected: $version" "Success"
        return $true
    } else {
        Write-ColorOutput "pip not found" "Error"
        return $false
    }
}

#########################################################
# Installation Functions
#########################################################

function Install-Python {
    Show-Section "Installing Python"

    Write-ColorOutput "Python installation options:" "Info"
    Write-Host ""
    Write-Host "  1) Download from Microsoft Store (Recommended)"
    Write-Host "  2) Download from python.org"
    Write-Host "  3) Install via winget"
    Write-Host "  0) Cancel"
    Write-Host ""

    $choice = Read-Host "Select installation method"

    switch ($choice) {
        "1" {
            Write-ColorOutput "Opening Microsoft Store..." "Info"
            Start-Process "ms-windows-store://pdp/?ProductId=9NRWMJP3717K"
            Write-ColorOutput "Please install Python from the Microsoft Store and run this script again" "Warning"
            pause
        }
        "2" {
            Write-ColorOutput "Opening python.org download page..." "Info"
            Start-Process "https://www.python.org/downloads/"
            Write-ColorOutput "Please download and install Python, then run this script again" "Warning"
            pause
        }
        "3" {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-ColorOutput "Installing Python via winget..." "Progress"
                winget install Python.Python.3.11
                Write-ColorOutput "Python installation completed" "Success"
            } else {
                Write-ColorOutput "winget not available on this system" "Error"
            }
        }
        default {
            Write-ColorOutput "Installation cancelled" "Warning"
        }
    }
}

function Install-Reticulum {
    param([bool]$UseWSL = $false)

    if ($UseWSL) {
        Install-ReticulumWSL
        return
    }

    Show-Section "Installing Reticulum Ecosystem"

    if (-not (Test-Python)) {
        Write-ColorOutput "Python is required but not installed" "Error"
        $install = Read-Host "Would you like to install Python now? (Y/n)"
        if ($install -ne 'n' -and $install -ne 'N') {
            Install-Python
            return
        }
    }

    Write-ColorOutput "Installing Reticulum components..." "Progress"

    # Get pip command
    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    # Install RNS
    Write-ColorOutput "Installing RNS (Reticulum Network Stack)..." "Progress"
    & $pip install rns --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "RNS installed successfully" "Success"
    } else {
        Write-ColorOutput "Failed to install RNS" "Error"
        return
    }

    # Install LXMF
    Write-ColorOutput "Installing LXMF..." "Progress"
    & $pip install lxmf --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "LXMF installed successfully" "Success"
    } else {
        Write-ColorOutput "Failed to install LXMF" "Error"
    }

    # Ask about NomadNet
    $installNomad = Read-Host "Install NomadNet (terminal client)? (Y/n)"
    if ($installNomad -ne 'n' -and $installNomad -ne 'N') {
        Write-ColorOutput "Installing NomadNet..." "Progress"
        & $pip install nomadnet --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "NomadNet installed successfully" "Success"
        } else {
            Write-ColorOutput "Failed to install NomadNet" "Error"
        }
    }

    Write-ColorOutput "Reticulum installation completed" "Success"
}

function Install-ReticulumWSL {
    Show-Section "Installing Reticulum in WSL"

    $distros = Get-WSLDistributions
    if ($distros.Count -eq 0) {
        Write-ColorOutput "No WSL distributions found" "Error"
        Write-ColorOutput "Install WSL first with: wsl --install" "Info"
        return
    }

    Write-Host "Available WSL distributions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $distros.Count; $i++) {
        Write-Host "  $($i + 1)) $($distros[$i])"
    }
    Write-Host ""

    $selection = Read-Host "Select distribution"
    $selectedDistro = $distros[[int]$selection - 1]

    if (-not $selectedDistro) {
        Write-ColorOutput "Invalid selection" "Error"
        return
    }

    Write-ColorOutput "Installing Reticulum in $selectedDistro..." "Progress"

    # Download the Linux script to WSL
    $scriptUrl = "https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh"
    $wslScript = "/tmp/rns_management_tool.sh"

    wsl -d $selectedDistro -- bash -c "curl -fsSL $scriptUrl -o $wslScript && chmod +x $wslScript"

    # Run the installer
    Write-ColorOutput "Launching installer in WSL..." "Info"
    wsl -d $selectedDistro -- bash -c "/tmp/rns_management_tool.sh"
}

function Install-RNODE {
    Show-Section "RNODE Installation"

    Write-Host "RNODE installation options:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Install via Python (Native Windows)"
    Write-Host "  2) Install via WSL (Recommended for USB devices)"
    Write-Host "  3) Use Web Flasher"
    Write-Host "  0) Back"
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            Write-ColorOutput "Installing rnodeconf..." "Progress"
            $pip = "pip"
            if (Get-Command pip3 -ErrorAction SilentlyContinue) {
                $pip = "pip3"
            }

            & $pip install rns --upgrade

            if (Get-Command rnodeconf -ErrorAction SilentlyContinue) {
                Write-ColorOutput "rnodeconf installed successfully" "Success"
                Write-Host ""
                Write-Host "Run 'rnodeconf --help' for usage information" -ForegroundColor Yellow
            } else {
                Write-ColorOutput "rnodeconf installation failed" "Error"
            }
        }
        "2" {
            if (Test-WSL) {
                Write-ColorOutput "Launching RNODE installer in WSL..." "Info"
                $distros = Get-WSLDistributions
                if ($distros.Count -gt 0) {
                    wsl -d $distros[0] -- bash -c "curl -fsSL https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh | bash -s -- --rnode"
                }
            } else {
                Write-ColorOutput "WSL not available" "Error"
                Write-ColorOutput "Install WSL with: wsl --install" "Info"
            }
        }
        "3" {
            Write-ColorOutput "Opening RNode Web Flasher..." "Info"
            Start-Process "https://github.com/liamcottle/rnode-flasher"
        }
    }

    pause
}

function Install-Sideband {
    Show-Section "Installing Sideband"

    Write-ColorOutput "Sideband is available for Windows as an executable" "Info"
    Write-Host ""
    Write-Host "Download options:" -ForegroundColor Cyan
    Write-Host "  1) Download Windows executable"
    Write-Host "  2) Install from source (requires Python)"
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            Write-ColorOutput "Opening Sideband releases page..." "Info"
            Start-Process "https://github.com/markqvist/Sideband/releases"
        }
        "2" {
            if (Test-Python) {
                Write-ColorOutput "Installing Sideband from source..." "Progress"
                $pip = "pip"
                if (Get-Command pip3 -ErrorAction SilentlyContinue) {
                    $pip = "pip3"
                }
                & $pip install sbapp
            } else {
                Write-ColorOutput "Python not found" "Error"
            }
        }
    }

    pause
}

#########################################################
# Service Management
#########################################################

function Show-Status {
    Show-Section "Reticulum Status"

    # Check if rnsd is running
    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue

    if ($rnsdProcess) {
        Write-ColorOutput "rnsd daemon: Running (PID: $($rnsdProcess.Id))" "Success"
    } else {
        Write-ColorOutput "rnsd daemon: Not running" "Warning"
    }

    Write-Host ""
    Write-Host "Installed Components:" -ForegroundColor Cyan

    # Check Python packages
    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    $packages = @("rns", "lxmf", "nomadnet")
    foreach ($package in $packages) {
        try {
            $version = & $pip show $package 2>$null | Select-String "Version:" | ForEach-Object { $_ -replace "Version:\s*", "" }
            if ($version) {
                Write-ColorOutput "$package : v$version" "Success"
            } else {
                Write-ColorOutput "$package : Not installed" "Info"
            }
        } catch {
            Write-ColorOutput "$package : Not installed" "Info"
        }
    }

    Write-Host ""

    # Show rnstatus if available
    if (Get-Command rnstatus -ErrorAction SilentlyContinue) {
        Write-Host "Network Status:" -ForegroundColor Cyan
        rnstatus
    }

    pause
}

function Start-RNSDaemon {
    Show-Section "Starting rnsd Daemon"

    if (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue) {
        Write-ColorOutput "rnsd is already running" "Warning"
        return
    }

    Write-ColorOutput "Starting rnsd daemon..." "Progress"

    try {
        Start-Process -FilePath "rnsd" -ArgumentList "--daemon" -NoNewWindow
        Start-Sleep -Seconds 2

        if (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue) {
            Write-ColorOutput "rnsd daemon started successfully" "Success"
        } else {
            Write-ColorOutput "rnsd daemon failed to start" "Error"
        }
    } catch {
        Write-ColorOutput "Failed to start rnsd: $_" "Error"
    }

    pause
}

function Stop-RNSDaemon {
    Show-Section "Stopping rnsd Daemon"

    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue

    if (-not $rnsdProcess) {
        Write-ColorOutput "rnsd is not running" "Warning"
        return
    }

    Write-ColorOutput "Stopping rnsd daemon..." "Progress"

    try {
        Stop-Process -Name "rnsd" -Force
        Start-Sleep -Seconds 2

        if (-not (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue)) {
            Write-ColorOutput "rnsd daemon stopped" "Success"
        } else {
            Write-ColorOutput "Failed to stop rnsd daemon" "Error"
        }
    } catch {
        Write-ColorOutput "Error stopping rnsd: $_" "Error"
    }

    pause
}

#########################################################
# Backup and Restore
#########################################################

function New-Backup {
    Show-Section "Creating Backup"

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    $backedUp = $false

    New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null

    if (Test-Path $reticulumDir) {
        Copy-Item -Path $reticulumDir -Destination $Script:BackupDir -Recurse -Force
        Write-ColorOutput "Backed up Reticulum config" "Success"
        $backedUp = $true
    }

    if (Test-Path $nomadDir) {
        Copy-Item -Path $nomadDir -Destination $Script:BackupDir -Recurse -Force
        Write-ColorOutput "Backed up NomadNet config" "Success"
        $backedUp = $true
    }

    if (Test-Path $lxmfDir) {
        Copy-Item -Path $lxmfDir -Destination $Script:BackupDir -Recurse -Force
        Write-ColorOutput "Backed up LXMF config" "Success"
        $backedUp = $true
    }

    if ($backedUp) {
        Write-ColorOutput "Backup saved to: $Script:BackupDir" "Success"
    } else {
        Write-ColorOutput "No configuration files found to backup" "Warning"
    }

    pause
}

function Restore-Backup {
    Show-Section "Restore Backup"

    $backups = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter ".reticulum_backup_*" | Sort-Object LastWriteTime -Descending

    if ($backups.Count -eq 0) {
        Write-ColorOutput "No backups found" "Warning"
        pause
        return
    }

    Write-Host "Available backups:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-Host "  $($i + 1)) $($backups[$i].Name) - $($backups[$i].LastWriteTime)"
    }
    Write-Host ""

    $selection = Read-Host "Select backup to restore (0 to cancel)"

    if ($selection -eq "0") {
        return
    }

    $selectedBackup = $backups[[int]$selection - 1]

    Write-Host ""
    Write-ColorOutput "WARNING: This will overwrite your current configuration!" "Warning"
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Write-ColorOutput "Restoring from: $($selectedBackup.FullName)" "Progress"

        $items = Get-ChildItem -Path $selectedBackup.FullName -Directory
        foreach ($item in $items) {
            $dest = Join-Path $env:USERPROFILE $item.Name
            Copy-Item -Path $item.FullName -Destination $dest -Recurse -Force
        }

        Write-ColorOutput "Backup restored successfully" "Success"
    }

    pause
}

#########################################################
# Main Menu
#########################################################

function Show-MainMenu {
    Show-Header

    Write-Host "Main Menu:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Install/Update Reticulum Ecosystem"
    Write-Host "  2) Install/Update via WSL"
    Write-Host "  3) Install/Configure RNODE"
    Write-Host "  4) Install Sideband"
    Write-Host "  5) System Status"
    Write-Host "  6) Start rnsd Daemon"
    Write-Host "  7) Stop rnsd Daemon"
    Write-Host "  8) Backup Configuration"
    Write-Host "  9) Restore Configuration"
    Write-Host "  0) Exit"
    Write-Host ""

    $choice = Read-Host "Select an option"
    return $choice
}

#########################################################
# Main Program
#########################################################

function Main {
    # Initialize log
    "=== RNS Management Tool for Windows Started ===" | Out-File -FilePath $Script:LogFile
    "Version: $Script:Version" | Out-File -FilePath $Script:LogFile -Append
    "Timestamp: $(Get-Date)" | Out-File -FilePath $Script:LogFile -Append

    # Main loop
    while ($true) {
        $choice = Show-MainMenu

        switch ($choice) {
            "1" { Install-Reticulum -UseWSL $false }
            "2" { Install-Reticulum -UseWSL $true }
            "3" { Install-RNODE }
            "4" { Install-Sideband }
            "5" { Show-Status }
            "6" { Start-RNSDaemon }
            "7" { Stop-RNSDaemon }
            "8" { New-Backup }
            "9" { Restore-Backup }
            "0" {
                Write-Host ""
                Write-ColorOutput "Thank you for using RNS Management Tool!" "Info"
                Write-Host ""
                "=== RNS Management Tool Ended ===" | Out-File -FilePath $Script:LogFile -Append
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
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -lt 6) {
    # PowerShell 5.1 and below are Windows-only
    $IsWindows = $true
}

if ($IsWindows -eq $false) {
    Write-Host "Error: This script is designed for Windows systems" -ForegroundColor Red
    Write-Host "For Linux/Mac, please use rns_management_tool.sh" -ForegroundColor Yellow
    exit 1
}

# Run main program
Main
