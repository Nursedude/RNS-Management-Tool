#########################################################
# pwsh/ui.ps1 — Color output, headers, progress display
# Dot-sourced by rns_management_tool.ps1
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
    Write-Host "║            Part of the MeshForge Ecosystem             ║" -ForegroundColor Cyan
    Write-Host "║                  Windows Edition                       ║" -ForegroundColor Cyan
    Write-Host "║                                                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Use pre-detected environment flags
    Write-Host "Platform:      " -NoNewline
    Write-Host "Windows $([Environment]::OSVersion.Version.Major).$([Environment]::OSVersion.Version.Minor)" -ForegroundColor Green

    Write-Host "Architecture:  " -NoNewline
    Write-Host "$env:PROCESSOR_ARCHITECTURE" -ForegroundColor Green

    Write-Host "Admin Rights:  " -NoNewline
    if ($Script:IsAdmin) {
        Write-Host "Yes" -ForegroundColor Green
    } else {
        Write-Host "No (some features may be limited)" -ForegroundColor Yellow
    }

    if ($Script:HasWSL) {
        Write-Host "WSL:           " -NoNewline
        Write-Host "Available" -ForegroundColor Green
    }

    if ($Script:IsRemoteSession) {
        Write-Host "Session:       " -NoNewline
        Write-Host "Remote" -ForegroundColor Yellow
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

function Show-QuickStatus {
    Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "│  " -ForegroundColor White -NoNewline
    Write-Host "Quick Status" -ForegroundColor Cyan -NoNewline
    Write-Host "                                           │" -ForegroundColor White
    Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor White

    # Check rnsd
    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue
    Write-Host "│  " -ForegroundColor White -NoNewline
    if ($rnsdProcess) {
        Write-Host "● rnsd: Running (PID $($rnsdProcess.Id))" -ForegroundColor Green -NoNewline
        $padLen = 36 - "● rnsd: Running (PID $($rnsdProcess.Id))".Length
        if ($padLen -lt 0) { $padLen = 0 }
        Write-Host (" " * $padLen) -NoNewline
    } else {
        Write-Host "○ rnsd: Stopped" -ForegroundColor Yellow -NoNewline
        Write-Host (" " * 22) -NoNewline
    }
    Write-Host "│" -ForegroundColor White

    # Check RNS version
    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) { $pip = "pip3" }
    try {
        $rnsVersion = & $pip show rns 2>$null | Select-String "Version:" | ForEach-Object { ($_ -replace "Version:\s*", "").Trim() }
    } catch { $rnsVersion = $null }

    Write-Host "│  " -ForegroundColor White -NoNewline
    if ($rnsVersion) {
        Write-Host "● RNS: v$rnsVersion" -ForegroundColor Green -NoNewline
        $padLen = 37 - "● RNS: v$rnsVersion".Length
        if ($padLen -lt 0) { $padLen = 0 }
        Write-Host (" " * $padLen) -NoNewline
    } else {
        Write-Host "○ RNS: Not installed" -ForegroundColor Yellow -NoNewline
        Write-Host (" " * 17) -NoNewline
    }
    Write-Host "│" -ForegroundColor White

    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host ""
}

function Show-MainMenu {
    Show-Header
    Show-QuickStatus

    Write-Host "Main Menu:" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- Installation ---" -ForegroundColor Cyan
    Write-Host "  1) Install/Update Reticulum (Native Windows)"
    Write-Host "  2) Install Reticulum in WSL"
    Write-Host "  3) Install/Configure RNODE Device"
    Write-Host "  4) Install Sideband"
    Write-Host "  5) Install NomadNet"
    Write-Host "  m) Install MeshChat"
    Write-Host ""
    Write-Host "  --- Management ---" -ForegroundColor Cyan
    Write-Host "  6) System Status & Diagnostics"
    Write-Host "  7) Manage Services"
    Write-Host "  8) Backup/Restore Configuration"
    Write-Host "  9) Advanced Options"
    Write-Host ""
    Write-Host "  0) Exit"
    Write-Host ""

    $choice = Read-Host "Select an option"
    return $choice
}
