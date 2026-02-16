#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/core.ps1 — Environment detection, logging, health checks
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: Initialize-Environment, Write-RnsLog (leveled logging), Invoke-LogRotation
    (1MB / 3 backups), Test-DiskSpace, Test-AvailableMemory, Invoke-StartupHealthCheck
#>

BeforeAll {
    $Script:CoreSource = Get-Content -Path "$PSScriptRoot/../pwsh/core.ps1" -Raw

    $Script:CoreAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:CoreSource, [ref]$null, [ref]$null
    )
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "Initialize-Environment function exists" {
        $Script:CoreSource | Should -Match 'function Initialize-Environment'
    }

    It "Write-RnsLog function exists" {
        $Script:CoreSource | Should -Match 'function Write-RnsLog'
    }

    It "Invoke-LogRotation function exists" {
        $Script:CoreSource | Should -Match 'function Invoke-LogRotation'
    }

    It "Test-DiskSpace function exists" {
        $Script:CoreSource | Should -Match 'function Test-DiskSpace'
    }

    It "Test-AvailableMemory function exists" {
        $Script:CoreSource | Should -Match 'function Test-AvailableMemory'
    }

    It "Invoke-StartupHealthCheck function exists" {
        $Script:CoreSource | Should -Match 'function Invoke-StartupHealthCheck'
    }

    It "core.ps1 has exactly 6 functions" {
        $functionCount = ([regex]::Matches(
            $Script:CoreSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 6
    }
}

# ─────────────────────────────────────────────────────────────
# Initialize-Environment
# ─────────────────────────────────────────────────────────────
Describe "Initialize-Environment" {

    Context "Admin rights detection" {

        It "Checks WindowsPrincipal for admin role" {
            $Script:CoreSource | Should -Match 'WindowsPrincipal.*WindowsIdentity'
        }

        It "Stores result in Script:IsAdmin" {
            $Script:CoreSource | Should -Match '\$Script:IsAdmin'
        }
    }

    Context "WSL availability detection" {

        It "Checks for wsl command availability" {
            $Script:CoreSource | Should -Match 'Get-Command wsl'
        }

        It "Stores result in Script:HasWSL" {
            $Script:CoreSource | Should -Match '\$Script:HasWSL'
        }
    }

    Context "Remote session detection" {

        It "Detects SSH sessions via SSH_CLIENT" {
            $Script:CoreSource | Should -Match 'SSH_CLIENT'
        }

        It "Detects SSH sessions via SSH_TTY" {
            $Script:CoreSource | Should -Match 'SSH_TTY'
        }

        It "Detects SSH sessions via SSH_CONNECTION" {
            $Script:CoreSource | Should -Match 'SSH_CONNECTION'
        }

        It "Detects RDP sessions via SESSIONNAME" {
            $Script:CoreSource | Should -Match 'SESSIONNAME.*RDP'
        }

        It "Detects PS Remoting via ServerRemoteHost" {
            $Script:CoreSource | Should -Match 'ServerRemoteHost'
        }

        It "Stores result in Script:IsRemoteSession" {
            $Script:CoreSource | Should -Match '\$Script:IsRemoteSession'
        }
    }

    Context "Terminal color capability" {

        It "Defaults color to true" {
            $Script:CoreSource | Should -Match '\$Script:HasColor = \$true'
        }

        It "Detects non-interactive sessions" {
            $Script:CoreSource | Should -Match 'UserInteractive'
        }

        It "Disables color for non-interactive sessions" {
            $Script:CoreSource | Should -Match '\$Script:HasColor = \$false'
        }
    }

    It "Logs environment detection results" {
        $Script:CoreSource | Should -Match 'Write-RnsLog.*Environment.*Admin.*WSL.*Remote.*Color'
    }
}

# ─────────────────────────────────────────────────────────────
# Write-RnsLog (Leveled Logging)
# ─────────────────────────────────────────────────────────────
Describe "Write-RnsLog: Leveled Logging" {

    It "Accepts Message and Level parameters" {
        $Script:CoreSource | Should -Match 'param\s*\(\s*\[string\]\$Message'
        $Script:CoreSource | Should -Match '\[string\]\$Level'
    }

    It "Defaults Level to INFO" {
        $Script:CoreSource | Should -Match '\$Level\s*=\s*"INFO"'
    }

    It "Formats log line with timestamp" {
        $Script:CoreSource | Should -Match 'Get-Date -Format "yyyy-MM-dd HH:mm:ss"'
    }

    It "Formats log line with level brackets" {
        $Script:CoreSource | Should -Match '\[.*timestamp.*\].*\[.*Level.*\]'
    }

    It "Supports DEBUG level" {
        $Script:CoreSource | Should -Match '"DEBUG".*LogLevelDebug'
    }

    It "Supports INFO level" {
        $Script:CoreSource | Should -Match '"INFO".*LogLevelInfo'
    }

    It "Supports WARN level" {
        $Script:CoreSource | Should -Match '"WARN".*LogLevelWarn'
    }

    It "Supports ERROR level" {
        $Script:CoreSource | Should -Match '"ERROR".*LogLevelError'
    }

    It "Filters messages by current log level" {
        $Script:CoreSource | Should -Match '\$levelNum -ge \$Script:CurrentLogLevel'
    }

    It "Writes to log file using Out-File -Append" {
        $fnIdx = $Script:CoreSource.IndexOf('function Write-RnsLog')
        $fnEnd = $Script:CoreSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:CoreSource.Length }
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Out-File.*LogFile.*Append'
    }

    It "Uses SilentlyContinue for log write errors" {
        $Script:CoreSource | Should -Match 'Out-File.*ErrorAction SilentlyContinue'
    }
}

# ─────────────────────────────────────────────────────────────
# Invoke-LogRotation
# ─────────────────────────────────────────────────────────────
Describe "Invoke-LogRotation" {

    Context "Rotation thresholds" {

        It "Uses 1MB (1048576 bytes) as rotation threshold" {
            $Script:CoreSource | Should -Match '1048576'
        }

        It "Keeps maximum 3 rotated logs" {
            $Script:CoreSource | Should -Match '\$maxRotations\s*=\s*3'
        }
    }

    Context "Rotation mechanics" {

        It "Checks log file existence before rotating" {
            $fnIdx = $Script:CoreSource.IndexOf('function Invoke-LogRotation')
            $block = $Script:CoreSource.Substring($fnIdx, 400)
            $block | Should -Match 'Test-Path.*LogFile'
        }

        It "Checks file size against threshold" {
            $Script:CoreSource | Should -Match 'logSize.*ge.*maxBytes'
        }

        It "Uses Move-Item for rotation" {
            $Script:CoreSource | Should -Match 'Move-Item.*LogFile'
        }

        It "Rotates numbered files in correct order (high to low)" {
            # for ($i = $maxRotations; $i -gt 1; $i--)
            $Script:CoreSource | Should -Match 'for.*maxRotations.*-gt 1'
        }

        It "Renames current log to .1" {
            $Script:CoreSource | Should -Match 'Move-Item.*LogFile.*\.1'
        }
    }

    Context "Legacy log cleanup" {

        It "Cleans up legacy timestamped log files" {
            $Script:CoreSource | Should -Match 'rns_management_\*\.log'
        }

        It "Keeps only 3 most recent legacy logs" {
            $Script:CoreSource | Should -Match '\$count.*-gt 3'
        }

        It "Sorts legacy logs by name descending" {
            $Script:CoreSource | Should -Match 'Sort-Object Name -Descending'
        }
    }
}

# ─────────────────────────────────────────────────────────────
# Test-DiskSpace
# ─────────────────────────────────────────────────────────────
Describe "Test-DiskSpace" {

    It "Has MinimumMB parameter defaulting to 500" {
        $Script:CoreSource | Should -Match '\$MinimumMB\s*=\s*500'
    }

    It "Returns boolean (true/false)" {
        $fnIdx = $Script:CoreSource.IndexOf('function Test-DiskSpace')
        $fnEnd = $Script:CoreSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:CoreSource.Length }
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$true'
        $block | Should -Match 'return \$false'
    }

    It "Reports critical at 100MB threshold" {
        $Script:CoreSource | Should -Match 'freeMB.*-lt 100'
    }

    It "Reports warning below MinimumMB" {
        $Script:CoreSource | Should -Match 'freeMB.*-lt.*MinimumMB'
    }

    It "Logs disk space at DEBUG level" {
        $Script:CoreSource | Should -Match 'Write-RnsLog.*Disk space.*DEBUG'
    }

    It "Logs critical disk space at ERROR level" {
        $Script:CoreSource | Should -Match 'Write-RnsLog.*Critical disk.*ERROR'
    }

    It "Logs low disk space at WARN level" {
        $Script:CoreSource | Should -Match 'Write-RnsLog.*Low disk.*WARN'
    }

    It "Does not block on check failure (returns true in catch)" {
        $fnIdx = $Script:CoreSource.IndexOf('function Test-DiskSpace')
        $fnEnd = $Script:CoreSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:CoreSource.Length }
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        # The catch block should return $true so we don't block startup
        $catchIdx = $block.LastIndexOf('catch')
        $catchBlock = $block.Substring($catchIdx)
        $catchBlock | Should -Match 'return \$true'
    }
}

# ─────────────────────────────────────────────────────────────
# Test-AvailableMemory
# ─────────────────────────────────────────────────────────────
Describe "Test-AvailableMemory" {

    It "Uses Win32_OperatingSystem CIM class" {
        $Script:CoreSource | Should -Match 'Get-CimInstance.*Win32_OperatingSystem'
    }

    It "Calculates percentage free" {
        $Script:CoreSource | Should -Match 'percentFree'
    }

    It "Warns when free memory below 10%" {
        $Script:CoreSource | Should -Match 'percentFree.*-lt 10'
    }

    It "Returns boolean (true/false)" {
        $fnIdx = $Script:CoreSource.IndexOf('function Test-AvailableMemory')
        $fnEnd = $Script:CoreSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:CoreSource.Length }
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$true'
        $block | Should -Match 'return \$false'
    }

    It "Logs memory stats at DEBUG level" {
        $Script:CoreSource | Should -Match 'Write-RnsLog.*Memory.*DEBUG'
    }

    It "Provides user hint to close applications" {
        $Script:CoreSource | Should -Match 'Close other applications'
    }

    It "Does not block on check failure (returns true in catch)" {
        $fnIdx = $Script:CoreSource.IndexOf('function Test-AvailableMemory')
        $fnEnd = $Script:CoreSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:CoreSource.Length }
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $catchIdx = $block.LastIndexOf('catch')
        $catchBlock = $block.Substring($catchIdx)
        $catchBlock | Should -Match 'return \$true'
    }
}

# ─────────────────────────────────────────────────────────────
# Invoke-StartupHealthCheck
# ─────────────────────────────────────────────────────────────
Describe "Invoke-StartupHealthCheck" {

    It "Initializes warnings counter" {
        $fnIdx = $Script:CoreSource.IndexOf('function Invoke-StartupHealthCheck')
        $block = $Script:CoreSource.Substring($fnIdx, 200)
        $block | Should -Match '\$warnings\s*=\s*0'
    }

    It "Runs disk space check" {
        $fnIdx = $Script:CoreSource.IndexOf('function Invoke-StartupHealthCheck')
        $fnEnd = $Script:CoreSource.Length
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Test-DiskSpace'
    }

    It "Runs memory check" {
        $fnIdx = $Script:CoreSource.IndexOf('function Invoke-StartupHealthCheck')
        $fnEnd = $Script:CoreSource.Length
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Test-AvailableMemory'
    }

    It "Tests log file writability" {
        $Script:CoreSource | Should -Match 'Out-File.*LogFile.*Append.*ErrorAction Stop'
    }

    It "Falls back to TEMP directory when log not writable" {
        $Script:CoreSource | Should -Match 'Join-Path.*TEMP.*rns_management\.log'
    }

    It "Detects remote session" {
        $fnIdx = $Script:CoreSource.IndexOf('function Invoke-StartupHealthCheck')
        $fnEnd = $Script:CoreSource.Length
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'IsRemoteSession'
    }

    It "Logs startup result with warning count" {
        $Script:CoreSource | Should -Match 'Write-RnsLog.*Startup health check completed.*warning'
    }

    It "Logs clean pass when no warnings" {
        $Script:CoreSource | Should -Match 'Write-RnsLog.*Startup health check passed'
    }

    It "Performs 4 health checks in sequence" {
        $fnIdx = $Script:CoreSource.IndexOf('function Invoke-StartupHealthCheck')
        $fnEnd = $Script:CoreSource.Length
        $block = $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
        # 1. Disk, 2. Memory, 3. Log writable, 4. Remote session
        $block | Should -Match '# 1\. Disk'
        $block | Should -Match '# 2\. Memory'
        $block | Should -Match '# 3\. Log writable'
        $block | Should -Match '# 4\. Remote session'
    }
}

# ─────────────────────────────────────────────────────────────
# RNS001: Command Safety (No Eval)
# ─────────────────────────────────────────────────────────────
Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:CoreSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:CoreSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }

    It "AST contains no Invoke-Expression commands" {
        $iexCmds = $Script:CoreAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-Expression'
        }, $true)
        $iexCmds.Count | Should -Be 0
    }
}
