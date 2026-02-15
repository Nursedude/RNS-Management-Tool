#########################################################
# pwsh/diagnostics.ps1 — System diagnostics (6-step)
# Dot-sourced by rns_management_tool.ps1
#########################################################

$Script:DiagIssues = 0
$Script:DiagWarnings = 0

function Invoke-DiagCheckEnvironment {
    Write-Host "▶ Step 1/6: Environment & Prerequisites" -ForegroundColor Blue
    Write-Host ""

    Write-Host "  Platform:      Windows $([Environment]::OSVersion.Version.Major).$([Environment]::OSVersion.Version.Minor)"
    Write-Host "  Architecture:  $env:PROCESSOR_ARCHITECTURE"
    Write-Host "  User:          $env:USERNAME"
    if ($Script:IsAdmin) {
        Write-Host "  Admin:         Yes" -ForegroundColor Green
    } else {
        Write-Host "  Admin:         No" -ForegroundColor Yellow
    }
    if ($Script:IsRemoteSession) {
        Write-Host "  Session:       Remote"
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $version = & python --version 2>&1
        Write-ColorOutput "$version" "Success"
        Write-Host "  Location:      $($python.Source)"
    } else {
        Write-ColorOutput "Python not found" "Error"
        Write-Host "  Fix: Install Python from python.org" -ForegroundColor Yellow
        $Script:DiagIssues++
    }

    $pip = Get-Command pip -ErrorAction SilentlyContinue
    if (-not $pip) { $pip = Get-Command pip3 -ErrorAction SilentlyContinue }
    if ($pip) {
        Write-ColorOutput "pip available" "Success"
    } else {
        Write-ColorOutput "pip not found" "Error"
        Write-Host "  Fix: python -m ensurepip --upgrade" -ForegroundColor Yellow
        $Script:DiagIssues++
    }
    Write-Host ""
}

function Invoke-DiagCheckRnsTool {
    Write-Host "▶ Step 2/6: RNS Tool Availability" -ForegroundColor Blue
    Write-Host ""

    $tools = @(
        @{ Name = "rnsd";      Desc = "daemon" },
        @{ Name = "rnstatus";  Desc = "network status" },
        @{ Name = "rnpath";    Desc = "path table" },
        @{ Name = "rnprobe";   Desc = "connectivity probe" },
        @{ Name = "rncp";      Desc = "file transfer" },
        @{ Name = "rnx";       Desc = "remote execution" },
        @{ Name = "rnid";      Desc = "identity management" },
        @{ Name = "rnodeconf"; Desc = "RNODE configuration" }
    )

    $missing = 0
    foreach ($tool in $tools) {
        if (Get-Command $tool.Name -ErrorAction SilentlyContinue) {
            Write-ColorOutput "$($tool.Name) ($($tool.Desc))" "Success"
        } else {
            Write-Host "  ○ $($tool.Name) ($($tool.Desc)) - not installed" -ForegroundColor Yellow
            $missing++
        }
    }

    if ($missing -gt 0) {
        Write-Host ""
        Write-Host "  [i] Install missing tools: pip install rns" -ForegroundColor Cyan
        $Script:DiagWarnings++
    }
    Write-Host ""
}

function Invoke-DiagCheckConfiguration {
    Write-Host "▶ Step 3/6: Configuration Validation" -ForegroundColor Blue
    Write-Host ""

    $configDir = Join-Path $env:USERPROFILE ".reticulum"
    $configFile = Join-Path $configDir "config"

    if (Test-Path $configFile) {
        Write-ColorOutput "Config file exists: $configFile" "Success"

        $configSize = (Get-Item $configFile).Length
        if ($configSize -lt 10) {
            Write-ColorOutput "Config file appears empty ($configSize bytes)" "Error"
            $Script:DiagIssues++
        }

        $content = Get-Content $configFile -Raw -ErrorAction SilentlyContinue
        if ($content -match "interface_enabled = false") {
            Write-ColorOutput "Some interfaces are disabled in config" "Warning"
            $Script:DiagWarnings++
        }
    } elseif (Test-Path $configDir) {
        Write-ColorOutput "Config directory exists but no config file" "Warning"
        Write-Host "  Fix: Run 'rnsd --daemon' to create default config" -ForegroundColor Yellow
        $Script:DiagWarnings++
    } else {
        Write-ColorOutput "No configuration found" "Warning"
        Write-Host "  Fix: Run 'rnsd --daemon' to create default config" -ForegroundColor Yellow
        $Script:DiagWarnings++
    }
    Write-Host ""
}

function Invoke-DiagCheckService {
    Write-Host "▶ Step 4/6: Service Health" -ForegroundColor Blue
    Write-Host ""

    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue
    if ($rnsdProcess) {
        Write-ColorOutput "rnsd daemon is running (PID: $($rnsdProcess.Id))" "Success"

        # Show uptime if available
        try {
            $startTime = $rnsdProcess.StartTime
            $uptime = (Get-Date) - $startTime
            if ($uptime.TotalMinutes -lt 1) {
                Write-Host "  Uptime: $([math]::Floor($uptime.TotalSeconds))s"
            } elseif ($uptime.TotalHours -lt 1) {
                Write-Host "  Uptime: $([math]::Floor($uptime.TotalMinutes))m"
            } else {
                Write-Host "  Uptime: $([math]::Floor($uptime.TotalHours))h $($uptime.Minutes)m"
            }
        } catch { Write-Verbose "Could not determine rnsd uptime: $_" }
    } else {
        Write-ColorOutput "rnsd daemon is not running" "Warning"
        Write-Host "  Fix: Start from Services menu or run: rnsd --daemon" -ForegroundColor Yellow
        $Script:DiagWarnings++
    }

    # WSL service check
    if ($Script:HasWSL) {
        Write-Host ""
        Write-Host "  WSL Integration:" -ForegroundColor Cyan
        try {
            $wslRnsd = wsl pgrep -x rnsd 2>$null
            if ($wslRnsd) {
                Write-ColorOutput "rnsd running inside WSL" "Success"
            } else {
                Write-Host "  [i] rnsd not running in WSL" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "  [i] Could not check WSL rnsd status" -ForegroundColor Cyan
        }
    }
    Write-Host ""
}

function Invoke-DiagCheckNetwork {
    Write-Host "▶ Step 5/6: Network & Interfaces" -ForegroundColor Blue
    Write-Host ""

    # Network adapters
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
        if ($adapters) {
            Write-ColorOutput "$($adapters.Count) network adapter(s) up" "Success"
            foreach ($adapter in $adapters) {
                Write-Host "  $($adapter.Name): $($adapter.InterfaceDescription)"
            }
        } else {
            Write-ColorOutput "No active network adapters found" "Warning"
            $Script:DiagWarnings++
        }
    } catch {
        Write-Host "  [i] Could not enumerate network adapters" -ForegroundColor Cyan
    }

    # USB serial devices
    Write-Host ""
    Write-Host "  USB Serial Devices:" -ForegroundColor Cyan
    try {
        $usbSerial = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'COM\d+' -and ($_.Name -match 'USB|Serial|CH340|CP210|FTDI|Silicon Labs') }
        if ($usbSerial -and $usbSerial.Count -gt 0) {
            Write-ColorOutput "$($usbSerial.Count) USB serial device(s) detected" "Success"
            foreach ($dev in $usbSerial) {
                Write-Host "    $($dev.Name)"
            }
        } else {
            # Fallback to basic serial port enumeration
            $serialPorts = [System.IO.Ports.SerialPort]::GetPortNames()
            if ($serialPorts.Count -gt 0) {
                Write-ColorOutput "$($serialPorts.Count) serial port(s) detected" "Success"
                foreach ($port in $serialPorts) {
                    Write-Host "    $port"
                }
            } else {
                Write-Host "    [i] No serial ports (RNODE) detected" -ForegroundColor Cyan
            }
        }
    } catch {
        try {
            $serialPorts = [System.IO.Ports.SerialPort]::GetPortNames()
            if ($serialPorts.Count -gt 0) {
                Write-ColorOutput "$($serialPorts.Count) serial port(s) detected" "Success"
                foreach ($port in $serialPorts) {
                    Write-Host "    $port"
                }
            } else {
                Write-Host "    [i] No serial ports (RNODE) detected" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "    [i] Could not enumerate serial ports" -ForegroundColor Cyan
        }
    }

    # RNS interface status
    if ((Get-Command rnstatus -ErrorAction SilentlyContinue) -and (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "  Reticulum Interface Status:" -ForegroundColor Cyan
        try {
            $rnstatusOutput = & rnstatus 2>&1 | Select-Object -First 25
            foreach ($line in $rnstatusOutput) {
                Write-Host "  $line"
            }
        } catch { Write-Verbose "Could not retrieve rnstatus output: $_" }
    }
    Write-Host ""
}

function Invoke-DiagReportSummary {
    Write-Host "▶ Step 6/6: Summary & Recommendations" -ForegroundColor Blue
    Write-Host ""

    if ($Script:DiagIssues -eq 0 -and $Script:DiagWarnings -eq 0) {
        Write-ColorOutput "All checks passed - system looks healthy" "Success"
    } else {
        if ($Script:DiagIssues -gt 0) {
            Write-ColorOutput "$($Script:DiagIssues) issue(s) found requiring attention" "Error"
        }
        if ($Script:DiagWarnings -gt 0) {
            Write-ColorOutput "$($Script:DiagWarnings) warning(s) found" "Warning"
        }
        Write-Host ""
        Write-Host "Recommended actions:" -ForegroundColor White

        if (-not (Get-Command rnsd -ErrorAction SilentlyContinue)) {
            Write-Host "  1. Install Reticulum: select option 1 from main menu"
        } elseif (-not (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue)) {
            Write-Host "  1. Start rnsd: select option 7 > 1 from main menu"
        }

        $configFile = Join-Path $env:USERPROFILE ".reticulum\config"
        if (-not (Test-Path $configFile)) {
            Write-Host "  2. Create configuration: run rnsd --daemon to generate default"
        }
    }

    Write-Host ""
    Write-RnsLog "Diagnostics complete: $($Script:DiagIssues) issues, $($Script:DiagWarnings) warnings" "INFO"
}

function Show-Diagnostic {
    Show-Section "System Diagnostics"

    $Script:DiagIssues = 0
    $Script:DiagWarnings = 0

    Write-Host "Running 6-step diagnostic..." -ForegroundColor White
    Write-Host ""

    Invoke-DiagCheckEnvironment
    Invoke-DiagCheckRnsTool
    Invoke-DiagCheckConfiguration
    Invoke-DiagCheckService
    Invoke-DiagCheckNetwork
    Invoke-DiagReportSummary

    pause
}
