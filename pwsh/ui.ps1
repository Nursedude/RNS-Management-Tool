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

    $boxWidth = 56  # inner width between ║ chars
    $border = "═" * $boxWidth

    # Helper: pad a string to center it within the box
    function Format-BoxLine {
        param([string]$Text)
        $pad = $boxWidth - $Text.Length
        if ($pad -lt 0) { $pad = 0 }
        $leftPad = [math]::Floor($pad / 2)
        $rightPad = $pad - $leftPad
        return "║" + (" " * $leftPad) + $Text + (" " * $rightPad) + "║"
    }

    Write-Host ("╔" + $border + "╗") -ForegroundColor Cyan
    Write-Host (Format-BoxLine "") -ForegroundColor Cyan
    Write-Host (Format-BoxLine "RNS MANAGEMENT TOOL v$($Script:Version)") -ForegroundColor Cyan
    Write-Host (Format-BoxLine "Complete Reticulum Network Stack Manager") -ForegroundColor Cyan
    Write-Host (Format-BoxLine "Part of the MeshForge Ecosystem") -ForegroundColor Cyan
    Write-Host (Format-BoxLine "Windows Edition") -ForegroundColor Cyan
    Write-Host (Format-BoxLine "") -ForegroundColor Cyan
    Write-Host ("╚" + $border + "╝") -ForegroundColor Cyan
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
    $innerWidth = 57  # inner width between │ chars
    $hLine = "─" * $innerWidth

    # Helper: write a content line padded to fit the box
    function Write-StatusLine {
        param([string]$Text, [string]$Color = "White")
        $pad = $innerWidth - 2 - $Text.Length  # 2 for leading "  "
        if ($pad -lt 0) { $pad = 0 }
        Write-Host "│  " -ForegroundColor White -NoNewline
        Write-Host $Text -ForegroundColor $Color -NoNewline
        Write-Host (" " * $pad) -NoNewline
        Write-Host "│" -ForegroundColor White
    }

    Write-Host ("┌" + $hLine + "┐") -ForegroundColor White
    Write-StatusLine "Quick Status" "Cyan"
    Write-Host ("├" + $hLine + "┤") -ForegroundColor White

    # Check rnsd
    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue
    if ($rnsdProcess) {
        Write-StatusLine "● rnsd: Running (PID $($rnsdProcess.Id))" "Green"
    } else {
        Write-StatusLine "○ rnsd: Stopped" "Yellow"
    }

    # Check RNS version
    $pipCmd = Get-PipCommand
    try {
        if ($pipCmd) {
            $rnsVersion = & $pipCmd show rns 2>$null | Select-String "Version:" | ForEach-Object { ($_ -replace "Version:\s*", "").Trim() }
        } else {
            $rnsVersion = Invoke-Pip show rns 2>$null | Select-String "Version:" | ForEach-Object { ($_ -replace "Version:\s*", "").Trim() }
        }
    } catch { $rnsVersion = $null }

    if ($rnsVersion) {
        Write-StatusLine "● RNS: v$rnsVersion" "Green"
    } else {
        Write-StatusLine "○ RNS: Not installed" "Yellow"
    }

    Write-Host ("└" + $hLine + "┘") -ForegroundColor White
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
    Write-Host "  m) Install MeshChatX"
    Write-Host ""
    Write-Host "  --- Management ---" -ForegroundColor Cyan
    Write-Host "  6) System Status & Diagnostics"
    Write-Host "  7) Manage Services"
    Write-Host "  8) Backup/Restore Configuration"
    Write-Host "  9) Advanced Options"
    Write-Host ""
    Write-Host "  l) Logs (system & app logs)"
    Write-Host "  0) Exit"
    Write-Host ""

    $choice = Read-Host "Select an option"
    return $choice
}
