#########################################################
# pwsh/core.ps1 — Environment detection, logging, globals
# Dot-sourced by rns_management_tool.ps1
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
    $Script:HasColor = $true
    if ($Host.Name -eq 'Windows PowerShell ISE Host') {
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

# Log rotation (adapted from meshforge 1MB rotation pattern)
function Invoke-LogRotation {
    $maxBytes = 1048576  # 1MB
    $maxRotations = 3

    if (-not (Test-Path $Script:LogFile)) { return }

    $logSize = (Get-Item $Script:LogFile -ErrorAction SilentlyContinue).Length
    if ($logSize -ge $maxBytes) {
        # Rotate: .log.3 -> delete, .log.2 -> .log.3, .log.1 -> .log.2, .log -> .log.1
        for ($i = $maxRotations; $i -gt 1; $i--) {
            $prev = $i - 1
            $src = "$($Script:LogFile).$prev"
            $dst = "$($Script:LogFile).$i"
            if (Test-Path $src) {
                Move-Item -Path $src -Destination $dst -Force
            }
        }
        Move-Item -Path $Script:LogFile -Destination "$($Script:LogFile).1" -Force
    }

    # Clean up legacy per-session timestamped log files
    $legacyLogs = Get-ChildItem -Path $Script:RealHome -Filter "rns_management_*.log" -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    $count = 0
    foreach ($logfile in $legacyLogs) {
        $count++
        if ($count -gt 3) {
            Remove-Item -Path $logfile.FullName -Force -ErrorAction SilentlyContinue
        }
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
        $Script:LogFile = Join-Path $env:TEMP "rns_management.log"
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
