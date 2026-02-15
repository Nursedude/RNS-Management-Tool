<#
.SYNOPSIS
    RNS Management Tool for Windows - Part of the MeshForge Ecosystem
.DESCRIPTION
    Complete Reticulum Network Stack Management Solution for Windows 11
    Supports native Windows and WSL2 installations

    This is the only MeshForge ecosystem tool with native Windows support.
    Upstream meshforge updates are frequent - check for updates regularly.
.NOTES
    Version: 0.3.0-beta
    Requires: PowerShell 5.1+ or PowerShell Core 7+
    Run as Administrator for best results
    MeshForge: https://github.com/Nursedude/meshforge
#>

#Requires -Version 5.1

# Resolve script directory reliably (meshforge pattern)
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Script configuration
$Script:Version = "0.3.0-beta"
# Note: $env:USERPROFILE is the correct home on Windows (no sudo/REAL_HOME issue)
$Script:RealHome = $env:USERPROFILE
$Script:LogFile = Join-Path $Script:RealHome "rns_management_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
# Environment Detection (adapted from meshforge patterns)
#########################################################

function Initialize-Environment {
    <#
    .SYNOPSIS
        Detects runtime environment capabilities (meshforge launcher.py pattern)
    #>

    # Admin rights check (meshforge system.py check_root equivalent)
    $Script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    # WSL availability
    $Script:HasWSL = [bool](Get-Command wsl -ErrorAction SilentlyContinue)

    # Remote/SSH session detection (meshforge launcher.py SSH detection)
    if ($env:SSH_CLIENT -or $env:SSH_TTY -or $env:SSH_CONNECTION) {
        $Script:IsRemoteSession = $true
    }
    # Also detect Windows Remote Desktop / PS Remoting
    if ($Host.Name -eq 'ServerRemoteHost' -or $env:SESSIONNAME -match 'RDP') {
        $Script:IsRemoteSession = $true
    }

    # Terminal capability detection (meshforge emoji.py pattern)
    # PowerShell ISE and some terminals have limited color support
    $Script:HasColor = $true
    if ($Host.Name -eq 'Windows PowerShell ISE Host') {
        # ISE uses its own color scheme - still works
        $Script:HasColor = $true
    }
    if (-not [Environment]::UserInteractive) {
        $Script:HasColor = $false
    }

    Write-RnsLog "Environment: Admin=$($Script:IsAdmin), WSL=$($Script:HasWSL), Remote=$($Script:IsRemoteSession), Color=$($Script:HasColor)" "INFO"
}

#########################################################
# Leveled Logging (adapted from meshforge logging_config.py)
#########################################################

function Write-RnsLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"

    # Filter by log level
    $levelNum = switch ($Level) {
        "DEBUG" { $Script:LogLevelDebug }
        "INFO"  { $Script:LogLevelInfo }
        "WARN"  { $Script:LogLevelWarn }
        "ERROR" { $Script:LogLevelError }
        default { $Script:LogLevelInfo }
    }

    if ($levelNum -ge $Script:CurrentLogLevel) {
        $logLine | Out-File -FilePath $Script:LogFile -Append -ErrorAction SilentlyContinue
    }
}

#########################################################
# Startup Health Check (adapted from meshforge startup_health.py)
#########################################################

function Test-DiskSpace {
    <#
    .SYNOPSIS
        Check available disk space (meshforge diagnostics pattern)
    #>
    param(
        [int]$MinimumMB = 500
    )

    try {
        $drive = (Get-Item $Script:RealHome).PSDrive
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $freeMB = [math]::Round($drive.Free / 1MB)

        Write-RnsLog "Disk space: ${freeGB}GB free on $($drive.Name): (minimum: ${MinimumMB}MB)" "DEBUG"

        if ($freeMB -lt 100) {
            Write-ColorOutput "Critical: Only ${freeMB}MB disk space available" "Error"
            Write-RnsLog "Critical disk space: ${freeMB}MB" "ERROR"
            return $false
        }
        elseif ($freeMB -lt $MinimumMB) {
            Write-ColorOutput "Low disk space: ${freeMB}MB available (recommend ${MinimumMB}MB)" "Warning"
            Write-RnsLog "Low disk space: ${freeMB}MB" "WARN"
            return $false
        }

        return $true
    }
    catch {
        Write-RnsLog "Could not check disk space: $_" "WARN"
        return $true  # Don't block on check failure
    }
}

function Test-AvailableMemory {
    <#
    .SYNOPSIS
        Check available system memory (meshforge system.py check_memory)
    #>

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
        $percentFree = [math]::Round(($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100)

        Write-RnsLog "Memory: ${freeMB}MB free of ${totalMB}MB (${percentFree}%)" "DEBUG"

        if ($percentFree -lt 10) {
            Write-ColorOutput "Low memory: ${freeMB}MB free (${percentFree}%)" "Warning"
            Write-ColorOutput "Hint: Close other applications to free memory" "Info"
            Write-RnsLog "Low memory: ${freeMB}MB free (${percentFree}%)" "WARN"
            return $false
        }

        return $true
    }
    catch {
        Write-RnsLog "Could not check memory: $_" "WARN"
        return $true
    }
}

function Invoke-StartupHealthCheck {
    <#
    .SYNOPSIS
        Run environment validation before entering main menu (meshforge startup_health.py)
    #>
    $warnings = 0

    Write-RnsLog "Running startup health check..." "INFO"

    # 1. Disk space
    if (-not (Test-DiskSpace -MinimumMB 500)) {
        $warnings++
    }

    # 2. Memory
    if (-not (Test-AvailableMemory)) {
        $warnings++
    }

    # 3. Log writable
    try {
        "test" | Out-File -FilePath $Script:LogFile -Append -ErrorAction Stop
    }
    catch {
        Write-ColorOutput "Cannot write to log file: $($Script:LogFile)" "Warning"
        $Script:LogFile = Join-Path $env:TEMP "rns_management_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Write-ColorOutput "Falling back to: $($Script:LogFile)" "Info"
        $warnings++
    }

    # 4. Remote session notice
    if ($Script:IsRemoteSession) {
        Write-RnsLog "Running via remote session (RDP/SSH/PSRemoting)" "DEBUG"
    }

    if ($warnings -gt 0) {
        Write-RnsLog "Startup health check completed with $warnings warning(s)" "WARN"
    }
    else {
        Write-RnsLog "Startup health check passed" "INFO"
    }
}

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

function Get-WSLDistribution {
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

    $distros = Get-WSLDistribution
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
                $distros = Get-WSLDistribution
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

function Install-NomadNet {
    Show-Section "Installing NomadNet"

    if (-not (Test-Python)) {
        Write-ColorOutput "Python is required but not installed" "Error"
        $install = Read-Host "Would you like to install Python now? (Y/n)"
        if ($install -ne 'n' -and $install -ne 'N') {
            Install-Python
            return
        }
    }

    Write-ColorOutput "Installing NomadNet terminal client..." "Progress"

    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    & $pip install nomadnet --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "NomadNet installed successfully" "Success"
        Write-Host ""
        Write-Host "Run 'nomadnet' to start the terminal client" -ForegroundColor Yellow
    } else {
        Write-ColorOutput "Failed to install NomadNet" "Error"
    }

    pause
}

function Install-MeshChat {
    Show-Section "Installing MeshChat"

    # Check for Node.js / npm
    $npm = Get-Command npm -ErrorAction SilentlyContinue

    if (-not $npm) {
        Write-ColorOutput "Node.js/npm not found" "Error"
        Write-Host ""
        Write-Host "MeshChat requires Node.js 18+. Install options:" -ForegroundColor Yellow
        Write-Host "  1) Download from https://nodejs.org/" -ForegroundColor Cyan
        Write-Host "  2) Install via winget: winget install OpenJS.NodeJS.LTS" -ForegroundColor Cyan
        Write-Host ""
        $installChoice = Read-Host "Install via winget now? (Y/n)"
        if ($installChoice -ne 'n' -and $installChoice -ne 'N') {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-ColorOutput "Installing Node.js LTS via winget..." "Progress"
                winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
                # Refresh PATH
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $npm = Get-Command npm -ErrorAction SilentlyContinue
                if (-not $npm) {
                    Write-ColorOutput "npm still not found after install. Restart your terminal and try again." "Error"
                    pause
                    return
                }
            } else {
                Write-ColorOutput "winget not available. Please install Node.js manually." "Error"
                pause
                return
            }
        } else {
            pause
            return
        }
    } else {
        $nodeVersion = & node --version 2>&1
        Write-ColorOutput "Node.js detected: $nodeVersion" "Success"
        # Check minimum version (18+)
        if ($nodeVersion -match 'v(\d+)') {
            $majorVersion = [int]$Matches[1]
            if ($majorVersion -lt 18) {
                Write-ColorOutput "Node.js $nodeVersion is too old. MeshChat requires Node.js 18+." "Error"
                Write-Host "  Fix: winget install OpenJS.NodeJS.LTS" -ForegroundColor Yellow
                pause
                return
            }
        }
    }

    # Check for git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "git not found. Install via: winget install Git.Git" "Error"
        pause
        return
    }

    $meshchatDir = Join-Path $env:USERPROFILE "reticulum-meshchat"
    $isUpdate = $false

    if (Test-Path $meshchatDir) {
        Write-ColorOutput "MeshChat directory already exists at $meshchatDir" "Warning"
        $update = Read-Host "Update existing installation? (Y/n)"
        if ($update -eq 'n' -or $update -eq 'N') {
            pause
            return
        }
        $isUpdate = $true
    }

    try {
        # Step 1: Clone or update
        if ($isUpdate) {
            Write-ColorOutput "Step 1/4: Updating repository..." "Progress"
            Push-Location $meshchatDir
            & git pull origin main 2>&1 | Out-File -FilePath $Script:LogFile -Append
        } else {
            Write-ColorOutput "Step 1/4: Cloning repository..." "Progress"
            & git clone https://github.com/liamcottle/reticulum-meshchat.git $meshchatDir 2>&1 | Out-File -FilePath $Script:LogFile -Append
            Push-Location $meshchatDir
        }

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Failed to clone/update MeshChat repository" "Error"
            Pop-Location
            pause
            return
        }

        # Step 2: npm install
        Write-ColorOutput "Step 2/4: Installing npm dependencies..." "Progress"
        & npm install 2>&1 | Out-File -FilePath $Script:LogFile -Append

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "npm install failed" "Error"
            Pop-Location
            pause
            return
        }

        # Step 3: Security audit (non-fatal)
        Write-ColorOutput "Step 3/4: Running security audit..." "Progress"
        & npm audit fix --audit-level=moderate 2>&1 | Out-File -FilePath $Script:LogFile -Append

        # Step 4: Build
        Write-ColorOutput "Step 4/4: Building application..." "Progress"
        & npm run build 2>&1 | Out-File -FilePath $Script:LogFile -Append

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Build failed" "Error"
            Pop-Location
            pause
            return
        }

        # Verify
        $packageJson = Join-Path $meshchatDir "package.json"
        if (Test-Path $packageJson) {
            $pkg = Get-Content $packageJson -Raw | ConvertFrom-Json
            Write-ColorOutput "MeshChat v$($pkg.version) installed successfully" "Success"
            Write-Host ""
            Write-Host "Start MeshChat with:" -ForegroundColor Yellow
            Write-Host "  cd $meshchatDir && npm start" -ForegroundColor Cyan
            Write-RnsLog "MeshChat installed: $($pkg.version)" "INFO"
        }

        Pop-Location
    }
    catch {
        Write-ColorOutput "MeshChat installation failed: $_" "Error"
        Pop-Location -ErrorAction SilentlyContinue
    }

    pause
}

#########################################################
# RNODE Advanced Functions (parity with bash script)
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

#########################################################
# Diagnostics - Step Functions (parity with bash script)
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

    # USB serial devices (enhanced: WMI for device identification)
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
        # Final fallback
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

function Show-BackupMenu {
    Show-Section "Backup/Restore Configuration"

    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  1) Create backup"
    Write-Host "  2) Restore backup"
    Write-Host "  0) Back"
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" { New-Backup }
        "2" { Restore-Backup }
        "0" { return }
    }
}

#########################################################
# Advanced Options Menu
#########################################################

function Show-AdvancedMenu {
    while ($true) {
        Show-Header
        Write-Host "Advanced Options:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1) Update Python Packages"
        Write-Host "  2) Reinstall All Components"
        Write-Host "  3) Clean Cache and Temporary Files"
        Write-Host "  4) Export Configuration"
        Write-Host "  5) Import Configuration"
        Write-Host "  6) Reset to Factory Defaults"
        Write-Host "  7) View Logs"
        Write-Host "  8) Check for Tool Updates"
        Write-Host "  0) Back to Main Menu"
        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1" { Update-PythonPackage }
            "2" { Install-Ecosystem }
            "3" { Clear-Cache }
            "4" { Export-Configuration }
            "5" { Import-Configuration }
            "6" { Reset-ToFactory }
            "7" { Show-Log }
            "8" { Test-ToolUpdate }
            "0" { return }
            default {
                Write-ColorOutput "Invalid option" "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Update-PythonPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Updating Python Packages"

    Write-ColorOutput "This will update pip and all Python packages" "Info"
    $confirm = Read-Host "Continue? (Y/n)"

    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        return
    }

    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    Write-ColorOutput "Updating pip..." "Progress"
    & $pip install --upgrade pip

    Write-ColorOutput "Updating setuptools and wheel..." "Progress"
    & $pip install --upgrade setuptools wheel

    Write-ColorOutput "Python packages updated" "Success"
    pause
}

function Install-Ecosystem {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Reinstalling All Components"

    Write-ColorOutput "WARNING: This will reinstall all Reticulum components" "Warning"
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        return
    }

    New-Backup
    Install-Reticulum -UseWSL $false
    pause
}

function Clear-Cache {
    Show-Section "Cleaning Cache"

    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    Write-ColorOutput "Clearing pip cache..." "Progress"
    & $pip cache purge 2>&1 | Out-File -FilePath $Script:LogFile -Append

    Write-ColorOutput "Clearing Windows temp files..." "Progress"
    $tempPath = [System.IO.Path]::GetTempPath()
    $removed = 0
    Get-ChildItem -Path $tempPath -Filter "rns*" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        $removed++
    }

    Write-ColorOutput "Cache cleaned ($removed items removed)" "Success"
    pause
}

function Export-Configuration {
    Show-Section "Export Configuration"

    $exportFile = Join-Path $env:USERPROFILE "reticulum_config_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"

    Write-ColorOutput "This will create a portable backup of your configuration" "Info"
    Write-Host ""

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    $hasConfig = $false
    if ((Test-Path $reticulumDir) -or (Test-Path $nomadDir) -or (Test-Path $lxmfDir)) {
        $hasConfig = $true
    }

    if (-not $hasConfig) {
        Write-ColorOutput "No configuration files found to export" "Warning"
        pause
        return
    }

    Write-ColorOutput "Creating export archive..." "Progress"

    # Create temporary directory
    $tempExport = Join-Path $env:TEMP "rns_export_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempExport -Force | Out-Null

    # Copy configs
    if (Test-Path $reticulumDir) {
        Copy-Item -Path $reticulumDir -Destination $tempExport -Recurse -Force
    }
    if (Test-Path $nomadDir) {
        Copy-Item -Path $nomadDir -Destination $tempExport -Recurse -Force
    }
    if (Test-Path $lxmfDir) {
        Copy-Item -Path $lxmfDir -Destination $tempExport -Recurse -Force
    }

    # Create zip archive
    Compress-Archive -Path "$tempExport\*" -DestinationPath $exportFile -Force

    # Cleanup
    Remove-Item -Path $tempExport -Recurse -Force

    Write-ColorOutput "Configuration exported to: $exportFile" "Success"
    "Exported configuration to: $exportFile" | Out-File -FilePath $Script:LogFile -Append

    pause
}

function Import-Configuration {
    Show-Section "Import Configuration"

    Write-Host "Enter the path to the export archive (.zip):" -ForegroundColor Cyan
    $importFile = Read-Host "Archive path"

    if (-not (Test-Path $importFile)) {
        Write-ColorOutput "File not found: $importFile" "Error"
        pause
        return
    }

    if ($importFile -notmatch '\.zip$') {
        Write-ColorOutput "Invalid file format. Expected .zip archive" "Error"
        pause
        return
    }

    # RNS004: Archive validation before extraction
    Write-ColorOutput "Validating archive structure..." "Info"

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($importFile)

        # Check for path traversal attempts
        $hasInvalidPaths = $false
        $hasReticulumConfig = $false

        foreach ($entry in $zip.Entries) {
            # Check for path traversal (../)
            if ($entry.FullName -match '\.\.' -or $entry.FullName.StartsWith('/') -or $entry.FullName.StartsWith('\')) {
                $hasInvalidPaths = $true
                break
            }
            # Check for expected Reticulum directories
            if ($entry.FullName -match '^\.reticulum|^\.nomadnetwork|^\.lxmf') {
                $hasReticulumConfig = $true
            }
        }

        $zip.Dispose()

        if ($hasInvalidPaths) {
            Write-ColorOutput "Security: Archive contains invalid paths (traversal attempt)" "Error"
            "SECURITY: Rejected archive with invalid paths: $importFile" | Out-File -FilePath $Script:LogFile -Append
            pause
            return
        }

        if (-not $hasReticulumConfig) {
            Write-ColorOutput "Archive does not appear to contain Reticulum configuration" "Warning"
            Write-Host "Expected directories: .reticulum/, .nomadnetwork/, .lxmf/"
            $continueAnyway = Read-Host "Continue anyway? (y/N)"
            if ($continueAnyway -ne 'y' -and $continueAnyway -ne 'Y') {
                Write-ColorOutput "Import cancelled" "Info"
                pause
                return
            }
        }

        Write-ColorOutput "Archive validation passed" "Success"
    }
    catch {
        Write-ColorOutput "Failed to validate archive: $_" "Error"
        pause
        return
    }

    Write-Host ""
    Write-ColorOutput "WARNING: This will overwrite your current configuration!" "Warning"
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-ColorOutput "Import cancelled" "Info"
        pause
        return
    }

    Write-ColorOutput "Creating backup of current configuration..." "Progress"
    New-Backup

    Write-ColorOutput "Importing configuration..." "Progress"

    try {
        # Extract to temp directory first
        $tempImport = Join-Path $env:TEMP "rns_import_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Expand-Archive -Path $importFile -DestinationPath $tempImport -Force

        # Copy to user profile
        Get-ChildItem -Path $tempImport -Directory | ForEach-Object {
            $dest = Join-Path $env:USERPROFILE $_.Name
            Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
        }

        # Cleanup
        Remove-Item -Path $tempImport -Recurse -Force

        Write-ColorOutput "Configuration imported successfully" "Success"
        "Imported configuration from: $importFile" | Out-File -FilePath $Script:LogFile -Append
    }
    catch {
        Write-ColorOutput "Failed to import configuration: $_" "Error"
    }

    pause
}

function Reset-ToFactory {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Reset to Factory Defaults"

    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                      WARNING!                          ║" -ForegroundColor Red
    Write-Host "║   This will DELETE all Reticulum configuration!        ║" -ForegroundColor Red
    Write-Host "║   Your identities and messages will be LOST forever!   ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "This will remove:" -ForegroundColor Yellow
    Write-Host "  • .reticulum/     (identities, keys, config)"
    Write-Host "  • .nomadnetwork/  (NomadNet data)"
    Write-Host "  • .lxmf/          (messages)"
    Write-Host ""

    $confirm = Read-Host "Type 'RESET' to confirm factory reset"

    if ($confirm -ne "RESET") {
        Write-ColorOutput "Reset cancelled - confirmation not received" "Info"
        pause
        return
    }

    Write-ColorOutput "Creating final backup before reset..." "Progress"
    New-Backup

    Write-ColorOutput "Removing configuration directories..." "Progress"

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    if (Test-Path $reticulumDir) {
        Remove-Item -Path $reticulumDir -Recurse -Force
        Write-ColorOutput "Removed .reticulum" "Success"
    }

    if (Test-Path $nomadDir) {
        Remove-Item -Path $nomadDir -Recurse -Force
        Write-ColorOutput "Removed .nomadnetwork" "Success"
    }

    if (Test-Path $lxmfDir) {
        Remove-Item -Path $lxmfDir -Recurse -Force
        Write-ColorOutput "Removed .lxmf" "Success"
    }

    Write-ColorOutput "Factory reset complete" "Success"
    Write-ColorOutput "Run 'rnsd --daemon' to create fresh configuration" "Info"
    "Factory reset performed - all configurations removed" | Out-File -FilePath $Script:LogFile -Append

    pause
}

function Show-Log {
    Show-Section "Recent Log Entries"

    if (Test-Path $Script:LogFile) {
        Write-Host "Last 50 log entries:" -ForegroundColor Cyan
        Write-Host ""
        Get-Content -Path $Script:LogFile -Tail 50
    }
    else {
        Write-ColorOutput "No log file found" "Warning"
    }

    pause
}

function Test-ToolUpdate {
    Show-Section "Checking for Updates"

    Write-ColorOutput "Checking GitHub for latest version..." "Progress"

    try {
        $latestUrl = "https://api.github.com/repos/Nursedude/RNS-Management-Tool/releases/latest"
        $response = Invoke-RestMethod -Uri $latestUrl -ErrorAction Stop

        $latestVersion = $response.tag_name -replace '^v', ''
        $currentVersion = $Script:Version

        Write-Host ""
        Write-Host "Current Version: $currentVersion" -ForegroundColor Cyan
        Write-Host "Latest Version:  $latestVersion" -ForegroundColor Cyan
        Write-Host ""

        if ($latestVersion -gt $currentVersion) {
            Write-ColorOutput "A new version is available!" "Success"
            Write-Host ""
            Write-Host "Download from: https://github.com/Nursedude/RNS-Management-Tool/releases/latest" -ForegroundColor Yellow
        }
        else {
            Write-ColorOutput "You are running the latest version" "Success"
        }
    }
    catch {
        Write-ColorOutput "Unable to check for updates: $_" "Error"
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
    [CmdletBinding(SupportsShouldProcess)]
    param()

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
    [CmdletBinding(SupportsShouldProcess)]
    param()

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
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Creating Backup"

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    $backedUp = $false

    if ($PSCmdlet.ShouldProcess($Script:BackupDir, "Create backup")) {
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

function Show-QuickStatus {
    Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "│  " -ForegroundColor White -NoNewline
    Write-Host "Quick Status" -ForegroundColor Cyan -NoNewline
    Write-Host "                                           │" -ForegroundColor White

    Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor White

    # Check rnsd status
    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue
    Write-Host "│  " -ForegroundColor White -NoNewline
    if ($rnsdProcess) {
        Write-Host "●" -ForegroundColor Green -NoNewline
        Write-Host " rnsd daemon: " -NoNewline
        Write-Host "Running" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "○" -ForegroundColor Red -NoNewline
        Write-Host " rnsd daemon: " -NoNewline
        Write-Host "Stopped" -ForegroundColor Yellow -NoNewline
    }
    Write-Host "                               │" -ForegroundColor White

    # Check RNS installed
    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) { $pip = "pip3" }

    Write-Host "│  " -ForegroundColor White -NoNewline
    try {
        $rnsVersion = & $pip show rns 2>$null | Select-String "Version:" | ForEach-Object { $_ -replace "Version:\s*", "" }
        if ($rnsVersion) {
            Write-Host "●" -ForegroundColor Green -NoNewline
            Write-Host " RNS: v$rnsVersion" -NoNewline
            Write-Host "                                          │" -ForegroundColor White
        } else {
            Write-Host "○" -ForegroundColor Yellow -NoNewline
            Write-Host " RNS: " -NoNewline
            Write-Host "Not installed" -ForegroundColor Yellow -NoNewline
            Write-Host "                                 │" -ForegroundColor White
        }
    } catch {
        Write-Host "○" -ForegroundColor Yellow -NoNewline
        Write-Host " RNS: " -NoNewline
        Write-Host "Not installed" -ForegroundColor Yellow -NoNewline
        Write-Host "                                 │" -ForegroundColor White
    }

    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host ""
}

function Show-MainMenu {
    Show-Header
    Show-QuickStatus

    Write-Host "Main Menu:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ─── Installation ───" -ForegroundColor Cyan
    Write-Host "  1) Install/Update Reticulum Ecosystem"
    Write-Host "  2) Install/Update via WSL"
    Write-Host "  3) RNODE Device Management"
    Write-Host "  4) Install Sideband"
    Write-Host "  5) Install NomadNet"
    Write-Host "  m) Install MeshChat"
    Write-Host ""
    Write-Host "  ─── Management ───" -ForegroundColor Cyan
    Write-Host "  6) System Status & Diagnostics"
    Write-Host "  7) Manage Services (Start/Stop rnsd)"
    Write-Host "  8) Backup/Restore Configuration"
    Write-Host "  9) Advanced Options"
    Write-Host ""
    Write-Host "  ─── System ───" -ForegroundColor Cyan
    Write-Host "  0) Exit"
    Write-Host ""
    Write-Host "Tip: " -ForegroundColor Yellow -NoNewline
    Write-Host "Run option 6 for detailed system diagnostics"
    Write-Host ""

    $choice = Read-Host "Select an option [0-9, m]"
    return $choice
}

#########################################################
# Main Program
#########################################################

#########################################################
# Service Menu - Helper Functions (parity with bash)
#########################################################

function Invoke-NetworkTool {
    param([string]$Tool)

    switch ($Tool) {
        "5" {
            Show-Section "Network Statistics"
            if (Get-Command rnstatus -ErrorAction SilentlyContinue) {
                & rnstatus -a 2>&1 | Select-Object -First 50
            } else {
                Write-ColorOutput "rnstatus not available - install RNS first" "Warning"
            }
        }
        "6" {
            Show-Section "Path Table"
            if (Get-Command rnpath -ErrorAction SilentlyContinue) {
                Write-ColorOutput "Known paths in the Reticulum network:" "Info"
                Write-Host ""
                & rnpath -t 2>&1
            } else {
                Write-ColorOutput "rnpath not available - install RNS first" "Warning"
            }
        }
        "7" {
            Show-Section "Probe Destination"
            if (Get-Command rnprobe -ErrorAction SilentlyContinue) {
                $dest = Read-Host "Enter destination hash to probe"
                if ($dest) {
                    Write-ColorOutput "Probing $dest..." "Info"
                    & rnprobe $dest 2>&1
                } else {
                    Write-ColorOutput "Cancelled" "Info"
                }
            } else {
                Write-ColorOutput "rnprobe not available - install RNS first" "Warning"
            }
        }
    }
    pause
}

function Invoke-IdentityManagement {
    Show-Section "Identity Management (rnid)"
    if (-not (Get-Command rnid -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rnid not available - install RNS first" "Warning"
        pause
        return
    }

    Write-Host "RNS Identity Management:" -ForegroundColor White
    Write-Host ""
    Write-Host "  1) Show my identity hash"
    Write-Host "  2) Generate new identity"
    Write-Host "  3) View identity file info"
    Write-Host "  0) Cancel"
    Write-Host ""

    $action = Read-Host "Select action"
    switch ($action) {
        "1" {
            Write-ColorOutput "Default identity hash:" "Info"
            & rnid 2>&1
        }
        "2" {
            $idDir = Join-Path $env:USERPROFILE ".reticulum\identities"
            if (-not (Test-Path $idDir)) {
                New-Item -ItemType Directory -Path $idDir -Force | Out-Null
            }
            $defaultPath = Join-Path $idDir "new_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            $outPath = Read-Host "Output path (default: $defaultPath)"
            if (-not $outPath) { $outPath = $defaultPath }
            Write-ColorOutput "Generating new identity..." "Info"
            & rnid -g $outPath 2>&1
            if (Test-Path $outPath) {
                Write-ColorOutput "Identity generated: $outPath" "Success"
            }
        }
        "3" {
            $filePath = Read-Host "Identity file path"
            if ($filePath -and (Test-Path $filePath)) {
                & rnid -i $filePath 2>&1
            } elseif ($filePath) {
                Write-ColorOutput "File not found: $filePath" "Error"
            } else {
                Write-ColorOutput "Cancelled" "Info"
            }
        }
        default { Write-ColorOutput "Cancelled" "Info" }
    }
    pause
}

function Show-ServiceMenu {
    while ($true) {
        Show-Section "Service Management"

        # Status box
        Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor White
        Write-Host "│  " -ForegroundColor White -NoNewline
        Write-Host "Service Status" -ForegroundColor Cyan -NoNewline
        Write-Host "                                         │" -ForegroundColor White
        Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor White
        $rnsdProc = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue
        Write-Host "│  " -ForegroundColor White -NoNewline
        if ($rnsdProc) {
            Write-Host "●" -ForegroundColor Green -NoNewline
            Write-Host " rnsd daemon: " -NoNewline
            Write-Host "Running" -ForegroundColor Green -NoNewline
        } else {
            Write-Host "○" -ForegroundColor Red -NoNewline
            Write-Host " rnsd daemon: " -NoNewline
            Write-Host "Stopped" -ForegroundColor Yellow -NoNewline
        }
        Write-Host "                               │" -ForegroundColor White
        Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor White
        Write-Host ""

        Write-Host "  --- rnsd Daemon Control ---" -ForegroundColor Cyan
        Write-Host "  1) Start rnsd daemon"
        Write-Host "  2) Stop rnsd daemon"
        Write-Host "  3) Restart rnsd daemon"
        Write-Host "  4) View detailed status"
        Write-Host ""

        # Network tools (show availability)
        Write-Host "  --- Network Tools ---" -ForegroundColor Cyan
        $hasRnstatus = [bool](Get-Command rnstatus -ErrorAction SilentlyContinue)
        $hasRnpath = [bool](Get-Command rnpath -ErrorAction SilentlyContinue)
        $hasRnprobe = [bool](Get-Command rnprobe -ErrorAction SilentlyContinue)
        $hasRnid = [bool](Get-Command rnid -ErrorAction SilentlyContinue)

        $s5 = if ($hasRnstatus) { "View network statistics (rnstatus)" } else { "View network statistics (rnstatus) [not installed]" }
        $s6 = if ($hasRnpath) { "View path table (rnpath)" } else { "View path table (rnpath) [not installed]" }
        $s7 = if ($hasRnprobe) { "Probe destination (rnprobe)" } else { "Probe destination (rnprobe) [not installed]" }
        Write-Host "  5) $s5"
        Write-Host "  6) $s6"
        Write-Host "  7) $s7"
        Write-Host ""

        Write-Host "  --- Identity ---" -ForegroundColor Cyan
        $s10 = if ($hasRnid) { "Identity management (rnid)" } else { "Identity management (rnid) [not installed]" }
        Write-Host "  10) $s10"
        Write-Host ""
        Write-Host "  0) Back to Main Menu"
        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1" { Start-RNSDaemon }
            "2" { Stop-RNSDaemon }
            "3" {
                Stop-RNSDaemon
                Start-Sleep -Seconds 2
                Start-RNSDaemon
            }
            "4" { Show-Status }
            { $_ -in "5","6","7" } { Invoke-NetworkTool $choice }
            "10" { Invoke-IdentityManagement }
            "0" { return }
            "" { return }
            default { Write-ColorOutput "Invalid option" "Error"; Start-Sleep -Seconds 1 }
        }
    }
}

function Main {
    # Initialize environment detection (meshforge pattern)
    Initialize-Environment

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
