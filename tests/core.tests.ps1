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

    # Helper: extract a function body from source by name.
    # Returns the text from "function <Name>" up to the next top-level function or EOF.
    function Get-FunctionBlock {
        param([string]$Name)
        $fnIdx = $Script:CoreSource.IndexOf("function $Name")
        if ($fnIdx -lt 0) { return $null }
        $fnEnd = $Script:CoreSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:CoreSource.Length }
        return $Script:CoreSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "Initialize-Environment function exists" {
        $Script:CoreSource.Contains('function Initialize-Environment') | Should -BeTrue
    }

    It "Write-RnsLog function exists" {
        $Script:CoreSource.Contains('function Write-RnsLog') | Should -BeTrue
    }

    It "Invoke-LogRotation function exists" {
        $Script:CoreSource.Contains('function Invoke-LogRotation') | Should -BeTrue
    }

    It "Test-DiskSpace function exists" {
        $Script:CoreSource.Contains('function Test-DiskSpace') | Should -BeTrue
    }

    It "Test-AvailableMemory function exists" {
        $Script:CoreSource.Contains('function Test-AvailableMemory') | Should -BeTrue
    }

    It "Invoke-StartupHealthCheck function exists" {
        $Script:CoreSource.Contains('function Invoke-StartupHealthCheck') | Should -BeTrue
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
            $Script:CoreSource.Contains('WindowsPrincipal') | Should -BeTrue
            $Script:CoreSource.Contains('WindowsIdentity') | Should -BeTrue
        }

        It "Stores result in Script:IsAdmin" {
            $Script:CoreSource.Contains('$Script:IsAdmin') | Should -BeTrue
        }
    }

    Context "WSL availability detection" {

        It "Checks for wsl command availability" {
            $Script:CoreSource.Contains('Get-Command wsl') | Should -BeTrue
        }

        It "Stores result in Script:HasWSL" {
            $Script:CoreSource.Contains('$Script:HasWSL') | Should -BeTrue
        }
    }

    Context "Remote session detection" {

        It "Detects SSH sessions via environment variables" {
            $Script:CoreSource.Contains('SSH_CLIENT') | Should -BeTrue
            $Script:CoreSource.Contains('SSH_TTY') | Should -BeTrue
            $Script:CoreSource.Contains('SSH_CONNECTION') | Should -BeTrue
        }

        It "Detects RDP sessions via SESSIONNAME" {
            $Script:CoreSource.Contains('SESSIONNAME') | Should -BeTrue
            $Script:CoreSource.Contains('RDP') | Should -BeTrue
        }

        It "Detects PS Remoting via ServerRemoteHost" {
            $Script:CoreSource.Contains('ServerRemoteHost') | Should -BeTrue
        }

        It "Stores result in Script:IsRemoteSession" {
            $Script:CoreSource.Contains('$Script:IsRemoteSession') | Should -BeTrue
        }
    }

    Context "Terminal color capability" {

        It "Defaults color to true and disables for non-interactive" {
            $Script:CoreSource.Contains('$Script:HasColor = $true') | Should -BeTrue
            $Script:CoreSource.Contains('UserInteractive') | Should -BeTrue
            $Script:CoreSource.Contains('$Script:HasColor = $false') | Should -BeTrue
        }
    }
}

# ─────────────────────────────────────────────────────────────
# Write-RnsLog (Leveled Logging)
# ─────────────────────────────────────────────────────────────
Describe "Write-RnsLog: Leveled Logging" {

    It "Accepts Message and Level parameters with INFO default" {
        $Script:CoreSource.Contains('[string]$Message') | Should -BeTrue
        $Script:CoreSource.Contains('[string]$Level') | Should -BeTrue
        $Script:CoreSource.Contains('$Level = "INFO"') | Should -BeTrue
    }

    It "Formats log line with timestamp" {
        $Script:CoreSource.Contains('Get-Date -Format "yyyy-MM-dd HH:mm:ss"') | Should -BeTrue
    }

    It "Filters messages by current log level" {
        $Script:CoreSource.Contains('$levelNum -ge $Script:CurrentLogLevel') | Should -BeTrue
    }

    It "Writes to log file with Out-File -Append and SilentlyContinue" {
        $block = Get-FunctionBlock 'Write-RnsLog'
        $block.Contains('Out-File') | Should -BeTrue
        $block.Contains('-Append') | Should -BeTrue
        $block.Contains('SilentlyContinue') | Should -BeTrue
    }
}

# ─────────────────────────────────────────────────────────────
# Invoke-LogRotation
# ─────────────────────────────────────────────────────────────
Describe "Invoke-LogRotation" {

    It "Uses 1MB (1048576 bytes) as rotation threshold" {
        $Script:CoreSource.Contains('1048576') | Should -BeTrue
    }

    It "Keeps maximum 3 rotated logs" {
        $Script:CoreSource.Contains('$maxRotations = 3') | Should -BeTrue
    }

    It "Checks log file existence and rotates with Move-Item" {
        $block = Get-FunctionBlock 'Invoke-LogRotation'
        $block.Contains('Test-Path') | Should -BeTrue
        $block.Contains('Move-Item') | Should -BeTrue
    }

    It "Cleans up legacy timestamped logs keeping only 3" {
        $Script:CoreSource.Contains('rns_management_*.log') | Should -BeTrue
        $Script:CoreSource.Contains('$count -gt 3') | Should -BeTrue
        $Script:CoreSource.Contains('Sort-Object Name -Descending') | Should -BeTrue
    }
}

# ─────────────────────────────────────────────────────────────
# Test-DiskSpace
# ─────────────────────────────────────────────────────────────
Describe "Test-DiskSpace" {

    It "Has MinimumMB parameter defaulting to 500" {
        $Script:CoreSource.Contains('$MinimumMB = 500') | Should -BeTrue
    }

    It "Returns boolean (true/false)" {
        $block = Get-FunctionBlock 'Test-DiskSpace'
        $block.Contains('return $true') | Should -BeTrue
        $block.Contains('return $false') | Should -BeTrue
    }

    It "Reports critical at 100MB threshold" {
        $Script:CoreSource.Contains('$freeMB -lt 100') | Should -BeTrue
    }

    It "Reports warning below MinimumMB" {
        $Script:CoreSource.Contains('$freeMB -lt $MinimumMB') | Should -BeTrue
    }

    It "Does not block on check failure (returns true in catch)" {
        $block = Get-FunctionBlock 'Test-DiskSpace'
        $catchIdx = $block.LastIndexOf('catch')
        $catchBlock = $block.Substring($catchIdx)
        $catchBlock.Contains('return $true') | Should -BeTrue
    }
}

# ─────────────────────────────────────────────────────────────
# Test-AvailableMemory
# ─────────────────────────────────────────────────────────────
Describe "Test-AvailableMemory" {

    It "Uses Win32_OperatingSystem CIM class" {
        $Script:CoreSource.Contains('Win32_OperatingSystem') | Should -BeTrue
    }

    It "Warns when free memory below 10%" {
        $Script:CoreSource.Contains('$percentFree -lt 10') | Should -BeTrue
    }

    It "Returns boolean (true/false)" {
        $block = Get-FunctionBlock 'Test-AvailableMemory'
        $block.Contains('return $true') | Should -BeTrue
        $block.Contains('return $false') | Should -BeTrue
    }

    It "Provides user hint to close applications" {
        $Script:CoreSource.Contains('Close other applications') | Should -BeTrue
    }

    It "Does not block on check failure (returns true in catch)" {
        $block = Get-FunctionBlock 'Test-AvailableMemory'
        $catchIdx = $block.LastIndexOf('catch')
        $catchBlock = $block.Substring($catchIdx)
        $catchBlock.Contains('return $true') | Should -BeTrue
    }
}

# ─────────────────────────────────────────────────────────────
# Invoke-StartupHealthCheck
# ─────────────────────────────────────────────────────────────
Describe "Invoke-StartupHealthCheck" {

    It "Initializes warnings counter" {
        $block = Get-FunctionBlock 'Invoke-StartupHealthCheck'
        $block.Contains('$warnings = 0') | Should -BeTrue
    }

    It "Runs disk space and memory checks" {
        $block = Get-FunctionBlock 'Invoke-StartupHealthCheck'
        $block.Contains('Test-DiskSpace') | Should -BeTrue
        $block.Contains('Test-AvailableMemory') | Should -BeTrue
    }

    It "Tests log file writability with fallback to TEMP" {
        $block = Get-FunctionBlock 'Invoke-StartupHealthCheck'
        $block.Contains('-ErrorAction Stop') | Should -BeTrue
        $block.Contains('rns_management.log') | Should -BeTrue
    }

    It "Detects remote session" {
        $block = Get-FunctionBlock 'Invoke-StartupHealthCheck'
        $block.Contains('IsRemoteSession') | Should -BeTrue
    }

    It "Logs startup result with warning count or clean pass" {
        $Script:CoreSource.Contains('Startup health check completed') | Should -BeTrue
        $Script:CoreSource.Contains('Startup health check passed') | Should -BeTrue
    }

    It "Performs 4 health checks in sequence" {
        $block = Get-FunctionBlock 'Invoke-StartupHealthCheck'
        $block.Contains('# 1. Disk') | Should -BeTrue
        $block.Contains('# 2. Memory') | Should -BeTrue
        $block.Contains('# 3. Log writable') | Should -BeTrue
        $block.Contains('# 4. Remote session') | Should -BeTrue
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
