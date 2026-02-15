#########################################################
# pwsh/rnode.ps1 — RNODE device configuration and management
# Dot-sourced by rns_management_tool.ps1
#########################################################

function Get-RnodeSerialPort {
    <#
    .SYNOPSIS
        Detect or prompt for RNODE serial port (RNS002 device port validation)
    #>

    # Enumerate serial ports with device details
    $ports = @()
    try {
        $serialPorts = [System.IO.Ports.SerialPort]::GetPortNames()
        if ($serialPorts.Count -gt 0) {
            $ports = $serialPorts
        }
    } catch { Write-Verbose "Serial port enumeration unavailable: $_" }

    # Also try WMI for richer device info
    $usbDevices = @()
    try {
        $usbDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'COM\d+' -and ($_.Name -match 'USB|Serial|CH340|CP210|FTDI|Silicon Labs') } |
            Select-Object Name, DeviceID
    } catch { Write-Verbose "USB device enumeration unavailable: $_" }

    if ($usbDevices.Count -gt 0) {
        Write-Host "Detected USB serial devices:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $usbDevices.Count; $i++) {
            Write-Host "  $($i + 1)) $($usbDevices[$i].Name)"
        }
        Write-Host "  0) Enter manually"
        Write-Host ""

        $sel = Read-Host "Select device"
        if ($sel -eq "0" -or -not $sel) {
            $port = Read-Host "Enter COM port (e.g., COM3)"
        } else {
            $idx = [int]$sel - 1
            if ($idx -ge 0 -and $idx -lt $usbDevices.Count) {
                if ($usbDevices[$idx].Name -match '(COM\d+)') {
                    $port = $Matches[1]
                }
            }
        }
    } elseif ($ports.Count -gt 0) {
        Write-Host "Available serial ports:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $ports.Count; $i++) {
            Write-Host "  $($i + 1)) $($ports[$i])"
        }
        Write-Host "  0) Enter manually"
        Write-Host ""

        $sel = Read-Host "Select port"
        if ($sel -eq "0" -or -not $sel) {
            $port = Read-Host "Enter COM port (e.g., COM3)"
        } else {
            $idx = [int]$sel - 1
            if ($idx -ge 0 -and $idx -lt $ports.Count) {
                $port = $ports[$idx]
            }
        }
    } else {
        Write-ColorOutput "No serial ports detected" "Warning"
        $port = Read-Host "Enter COM port manually (e.g., COM3)"
    }

    # RNS002: Validate COM port format
    if (-not $port -or $port -notmatch '^COM\d+$') {
        Write-ColorOutput "Invalid port format. Expected COMn (e.g., COM3)" "Error"
        return $null
    }

    return $port
}

function Set-RnodeRadioParameter {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    <#
    .SYNOPSIS
        Configure RNODE radio parameters (parity with bash rnode_configure_radio)
        Implements RNS003 numeric range validation
    #>
    Show-Section "Configure Radio Parameters"

    if (-not (Get-Command rnodeconf -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rnodeconf not installed. Install RNS first." "Error"
        pause
        return
    }

    $port = Get-RnodeSerialPort
    if (-not $port) { pause; return }

    Write-Host ""
    Write-Host "Radio Parameter Configuration" -ForegroundColor Cyan
    Write-Host "Leave blank to keep current value" -ForegroundColor White
    Write-Host ""

    # Build command arguments as array (RNS001: no eval)
    $cmdArgs = @($port)

    # Frequency (RNS003: numeric validation)
    $freq = Read-Host "Frequency in Hz (e.g., 915000000 for 915MHz)"
    if ($freq) {
        if ($freq -match '^\d+$') {
            $cmdArgs += "--freq"
            $cmdArgs += $freq
        } else {
            Write-ColorOutput "Invalid frequency - must be numeric. Skipping." "Warning"
        }
    }

    # Bandwidth (RNS003: numeric validation)
    $bw = Read-Host "Bandwidth in kHz (e.g., 125, 250, 500)"
    if ($bw) {
        if ($bw -match '^\d+$') {
            $cmdArgs += "--bw"
            $cmdArgs += $bw
        } else {
            Write-ColorOutput "Invalid bandwidth - must be numeric. Skipping." "Warning"
        }
    }

    # Spreading Factor (RNS003: range 7-12)
    $sf = Read-Host "Spreading Factor (7-12)"
    if ($sf) {
        if ($sf -match '^\d+$' -and [int]$sf -ge 7 -and [int]$sf -le 12) {
            $cmdArgs += "--sf"
            $cmdArgs += $sf
        } else {
            Write-ColorOutput "Invalid spreading factor - must be 7-12. Skipping." "Warning"
        }
    }

    # Coding Rate (RNS003: range 5-8)
    $cr = Read-Host "Coding Rate (5-8)"
    if ($cr) {
        if ($cr -match '^\d+$' -and [int]$cr -ge 5 -and [int]$cr -le 8) {
            $cmdArgs += "--cr"
            $cmdArgs += $cr
        } else {
            Write-ColorOutput "Invalid coding rate - must be 5-8. Skipping." "Warning"
        }
    }

    # TX Power (RNS003: range -10 to 30)
    $txp = Read-Host "TX Power in dBm (e.g., 17)"
    if ($txp) {
        if ($txp -match '^-?\d+$' -and [int]$txp -ge -10 -and [int]$txp -le 30) {
            $cmdArgs += "--txp"
            $cmdArgs += $txp
        } else {
            Write-ColorOutput "Invalid TX power - must be between -10 and 30 dBm. Skipping." "Warning"
        }
    }

    Write-Host ""
    Write-ColorOutput "Executing: rnodeconf $($cmdArgs -join ' ')" "Info"
    & rnodeconf @cmdArgs 2>&1
    Write-RnsLog "RNODE radio config: rnodeconf $($cmdArgs -join ' ')" "INFO"

    pause
}

function Get-RnodeEeprom {
    <#
    .SYNOPSIS
        View device EEPROM (parity with bash rnode_eeprom)
    #>
    Show-Section "View Device EEPROM"

    if (-not (Get-Command rnodeconf -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rnodeconf not installed. Install RNS first." "Error"
        pause
        return
    }

    $port = Get-RnodeSerialPort
    if (-not $port) { pause; return }

    Write-ColorOutput "Reading device EEPROM..." "Info"
    & rnodeconf $port --eeprom 2>&1
    Write-RnsLog "RNODE EEPROM read on $port" "INFO"

    pause
}

function Update-RnodeBootloader {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    <#
    .SYNOPSIS
        Update bootloader ROM (parity with bash rnode_bootloader)
    #>
    Show-Section "Update Bootloader (ROM)"

    if (-not (Get-Command rnodeconf -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rnodeconf not installed. Install RNS first." "Error"
        pause
        return
    }

    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  WARNING: This will update the device bootloader.      ║" -ForegroundColor Yellow
    Write-Host "║  Only proceed if you know what you're doing!           ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""

    $port = Get-RnodeSerialPort
    if (-not $port) { pause; return }

    # RNS005: Confirmation for destructive actions
    $confirm = Read-Host "Are you sure you want to update the bootloader? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-ColorOutput "Bootloader update cancelled" "Info"
        pause
        return
    }

    Write-ColorOutput "Updating bootloader..." "Info"
    & rnodeconf $port --rom 2>&1
    Write-RnsLog "RNODE bootloader update on $port" "INFO"

    pause
}

function Open-RnodeConsole {
    <#
    .SYNOPSIS
        Open serial console (parity with bash rnode_serial_console)
    #>
    Show-Section "Open Serial Console"

    if (-not (Get-Command rnodeconf -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rnodeconf not installed. Install RNS first." "Error"
        pause
        return
    }

    $port = Get-RnodeSerialPort
    if (-not $port) { pause; return }

    Write-ColorOutput "Opening serial console for $port..." "Info"
    Write-ColorOutput "Press Ctrl+C to exit" "Info"
    Write-Host ""
    & rnodeconf $port --console 2>&1

    pause
}

function Show-RnodeMenu {
    <#
    .SYNOPSIS
        RNODE management submenu (extends Install-RNODE with advanced features)
    #>
    while ($true) {
        Show-Section "RNODE Device Management"

        $hasRnodeconf = [bool](Get-Command rnodeconf -ErrorAction SilentlyContinue)

        Write-Host "  --- Installation ---" -ForegroundColor Cyan
        Write-Host "  1) Install/Update rnodeconf (pip)"
        Write-Host "  2) Install via WSL (for USB devices)"
        Write-Host "  3) Use Web Flasher"
        Write-Host ""
        Write-Host "  --- Configuration ---" -ForegroundColor Cyan
        $r4 = if ($hasRnodeconf) { "Configure radio parameters" } else { "Configure radio parameters [rnodeconf not installed]" }
        $r5 = if ($hasRnodeconf) { "View device EEPROM" } else { "View device EEPROM [rnodeconf not installed]" }
        $r6 = if ($hasRnodeconf) { "Update bootloader (ROM)" } else { "Update bootloader (ROM) [rnodeconf not installed]" }
        $r7 = if ($hasRnodeconf) { "Open serial console" } else { "Open serial console [rnodeconf not installed]" }
        $r8 = if ($hasRnodeconf) { "Show rnodeconf help" } else { "Show rnodeconf help [rnodeconf not installed]" }
        Write-Host "  4) $r4"
        Write-Host "  5) $r5"
        Write-Host "  6) $r6"
        Write-Host "  7) $r7"
        Write-Host "  8) $r8"
        Write-Host ""
        Write-Host "  0) Back to Main Menu"
        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1" {
                Write-ColorOutput "Installing rnodeconf..." "Progress"
                $pip = "pip"
                if (Get-Command pip3 -ErrorAction SilentlyContinue) { $pip = "pip3" }
                & $pip install rns --upgrade
                if (Get-Command rnodeconf -ErrorAction SilentlyContinue) {
                    Write-ColorOutput "rnodeconf installed successfully" "Success"
                } else {
                    Write-ColorOutput "rnodeconf installation failed" "Error"
                }
                pause
            }
            "2" {
                if (Test-WSL) {
                    Write-ColorOutput "Launching RNODE installer in WSL..." "Info"
                    $distros = Get-WSLDistribution
                    if ($distros.Count -gt 0) {
                        wsl -d $distros[0] -- bash -c "curl -fsSL https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh | bash -s -- --rnode"
                    }
                } else {
                    Write-ColorOutput "WSL not available. Install with: wsl --install" "Error"
                }
                pause
            }
            "3" {
                Write-ColorOutput "Opening RNode Web Flasher..." "Info"
                Start-Process "https://github.com/liamcottle/rnode-flasher"
                pause
            }
            "4" { Set-RnodeRadioParameter }
            "5" { Get-RnodeEeprom }
            "6" { Update-RnodeBootloader }
            "7" { Open-RnodeConsole }
            "8" {
                if ($hasRnodeconf) {
                    Show-Section "RNODE Configuration Help"
                    & rnodeconf --help 2>&1
                } else {
                    Write-ColorOutput "rnodeconf not installed" "Warning"
                }
                pause
            }
            "0" { return }
            "" { return }
            default { Write-ColorOutput "Invalid option" "Error"; Start-Sleep -Seconds 1 }
        }
    }
}
