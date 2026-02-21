#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/services.ps1 — Service management, autostart, network tools
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: daemon control, autostart (Task Scheduler), network tool dispatch,
    identity management, file transfer, remote command, menu structure, security
#>

BeforeAll {
    $Script:ServicesSource = Get-Content -Path "$PSScriptRoot/../pwsh/services.ps1" -Raw

    $Script:ServicesAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:ServicesSource, [ref]$null, [ref]$null
    )
}

# ---------------------------------------------------------
# Function Existence
# ---------------------------------------------------------
Describe "Function Existence" {

    It "services.ps1 has exactly 10 functions" {
        $functionCount = ([regex]::Matches(
            $Script:ServicesSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 10
    }
}

# ---------------------------------------------------------
# Daemon Control -- Start-RNSDaemon
# ---------------------------------------------------------
Describe "Daemon Control: Start-RNSDaemon" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Start-RNSDaemon')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:StartBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Start-RNSDaemon uses SupportsShouldProcess" {
        $Script:StartBlock.Contains('[CmdletBinding(SupportsShouldProcess)]') | Should -BeTrue
    }

    It "Checks if rnsd is already running before starting" {
        $Script:StartBlock.Contains('Get-Process') | Should -BeTrue
        $Script:StartBlock.Contains('already running') | Should -BeTrue
    }

    It "Uses Start-Process with --daemon argument" {
        $Script:StartBlock.Contains('Start-Process') | Should -BeTrue
        $Script:StartBlock.Contains('--daemon') | Should -BeTrue
    }

    It "Waits after starting for daemon to initialize" {
        $Script:StartBlock.Contains('Start-Sleep') | Should -BeTrue
    }

    It "Verifies daemon started after launch" {
        $startIdx = $Script:StartBlock.IndexOf('Start-Process')
        $verifyIdx = $Script:StartBlock.IndexOf('started successfully', $startIdx)
        $verifyIdx | Should -BeGreaterThan $startIdx
    }

    It "Reports error if daemon fails to start" {
        $Script:StartBlock.Contains('failed to start') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# Daemon Control -- Stop-RNSDaemon
# ---------------------------------------------------------
Describe "Daemon Control: Stop-RNSDaemon" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Stop-RNSDaemon')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:StopBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Stop-RNSDaemon uses SupportsShouldProcess" {
        $Script:StopBlock.Contains('[CmdletBinding(SupportsShouldProcess)]') | Should -BeTrue
    }

    It "Checks if rnsd is running before stopping" {
        $Script:StopBlock.Contains('Get-Process') | Should -BeTrue
    }

    It "Reports when rnsd is not running" {
        $Script:StopBlock.Contains('rnsd is not running') | Should -BeTrue
    }

    It "Uses Stop-Process with Force to terminate daemon" {
        $Script:StopBlock.Contains('Stop-Process') | Should -BeTrue
        $Script:StopBlock.Contains('-Force') | Should -BeTrue
    }

    It "Verifies daemon stopped after termination" {
        $Script:StopBlock.Contains('daemon stopped') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# Daemon Control -- Restart
# ---------------------------------------------------------
Describe "Daemon Control: Restart" {

    It "Menu option 3 calls Stop then Start on the same line" {
        # Line 352: "3"  { Stop-RNSDaemon; Start-RNSDaemon }
        $Script:ServicesSource.Contains('Stop-RNSDaemon; Start-RNSDaemon') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# Show-Status
# ---------------------------------------------------------
Describe "Show-Status" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Show-Status')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:StatusBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Displays rnsd process status" {
        $Script:StatusBlock.Contains('Get-Process') | Should -BeTrue
    }

    It "Shows installed component versions via pip" {
        $Script:StatusBlock.Contains('pip show') | Should -BeTrue
    }

    It "Checks rns, lxmf, and nomadnet packages" {
        $Script:StatusBlock.Contains('"rns"') | Should -BeTrue
        $Script:StatusBlock.Contains('"lxmf"') | Should -BeTrue
        $Script:StatusBlock.Contains('"nomadnet"') | Should -BeTrue
    }

    It "Shows rnstatus output when available" {
        $Script:StatusBlock.Contains('Get-Command rnstatus') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# Network Tool Dispatch
# ---------------------------------------------------------
Describe "Network Tool Dispatch: Invoke-NetworkTool" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Invoke-NetworkTool')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:NetToolBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Validates tool availability before execution" {
        $Script:NetToolBlock.Contains('Get-Command $Tool') | Should -BeTrue
    }

    It "Reports error for missing tools" {
        $Script:NetToolBlock.Contains('not installed') | Should -BeTrue
        $Script:NetToolBlock.Contains('Install RNS first') | Should -BeTrue
    }

    It "Handles rnstatus tool" {
        $Script:NetToolBlock.Contains('& rnstatus') | Should -BeTrue
    }

    It "Handles rnpath tool with -t flag" {
        $Script:NetToolBlock.Contains('& rnpath -t') | Should -BeTrue
    }

    It "Handles rnprobe with user-supplied destination" {
        $Script:NetToolBlock.Contains('Enter destination hash') | Should -BeTrue
        $Script:NetToolBlock.Contains('& rnprobe') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# Identity Management
# ---------------------------------------------------------
Describe "Identity Management: Invoke-IdentityManagement" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Invoke-IdentityManagement')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:IdentityBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks rnid availability" {
        $Script:IdentityBlock.Contains('Get-Command rnid') | Should -BeTrue
    }

    It "Offers show identity hash option" {
        $Script:IdentityBlock.Contains('Show identity hash') | Should -BeTrue
    }

    It "Offers generate new identity option" {
        $Script:IdentityBlock.Contains('Generate new identity') | Should -BeTrue
    }

    It "Offers view identity file location option" {
        $Script:IdentityBlock.Contains('View identity file location') | Should -BeTrue
    }

    It "Stores identities in .reticulum identities directory" {
        $Script:IdentityBlock.Contains('.reticulum') | Should -BeTrue
        $Script:IdentityBlock.Contains('identities') | Should -BeTrue
    }

    It "Creates identities directory if missing" {
        $Script:IdentityBlock.Contains('New-Item') | Should -BeTrue
        $Script:IdentityBlock.Contains('Directory') | Should -BeTrue
        $Script:IdentityBlock.Contains('identityDir') | Should -BeTrue
    }

    It "Uses rnid --generate for new identities" {
        $Script:IdentityBlock.Contains('rnid --generate') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# File Transfer
# ---------------------------------------------------------
Describe "File Transfer: Invoke-FileTransfer" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Invoke-FileTransfer')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:FileTransferBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks rncp availability" {
        $Script:FileTransferBlock.Contains('Get-Command rncp') | Should -BeTrue
    }

    It "Validates file exists before sending" {
        $Script:FileTransferBlock.Contains('Test-Path $filePath') | Should -BeTrue
    }

    It "Reports error for missing files" {
        $Script:FileTransferBlock.Contains('File not found') | Should -BeTrue
    }

    It "Offers listen mode for incoming transfers" {
        $Script:FileTransferBlock.Contains('rncp --listen') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# Remote Command
# ---------------------------------------------------------
Describe "Remote Command: Invoke-RemoteCommand" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Invoke-RemoteCommand')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:RemoteCmdBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks rnx availability" {
        $Script:RemoteCmdBlock.Contains('Get-Command rnx') | Should -BeTrue
    }

    It "Requires destination hash" {
        $Script:RemoteCmdBlock.Contains('No destination specified') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# Autostart via Task Scheduler
# ---------------------------------------------------------
Describe "Autostart: Enable-RnsdAutoStart" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Enable-RnsdAutoStart')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:EnableBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Verifies rnsd is installed before creating task" {
        $Script:EnableBlock.Contains('Get-Command rnsd') | Should -BeTrue
    }

    It "Uses consistent task name 'RNS_rnsd_autostart'" {
        $Script:EnableBlock.Contains('RNS_rnsd_autostart') | Should -BeTrue
    }

    It "Checks for existing scheduled task before creating" {
        $Script:EnableBlock.Contains('Get-ScheduledTask') | Should -BeTrue
        $Script:EnableBlock.Contains('$taskName') | Should -BeTrue
    }

    It "Asks confirmation before replacing existing task" {
        $Script:EnableBlock.Contains('Replace existing task') | Should -BeTrue
    }

    It "Unregisters old task before creating replacement" {
        $Script:EnableBlock.Contains('Unregister-ScheduledTask') | Should -BeTrue
        $Script:EnableBlock.Contains('-Confirm:$false') | Should -BeTrue
    }

    It "Creates task action with rnsd --daemon" {
        $Script:EnableBlock.Contains('New-ScheduledTaskAction') | Should -BeTrue
        $Script:EnableBlock.Contains('--daemon') | Should -BeTrue
    }

    It "Uses AtLogOn trigger" {
        $Script:EnableBlock.Contains('New-ScheduledTaskTrigger') | Should -BeTrue
        $Script:EnableBlock.Contains('-AtLogOn') | Should -BeTrue
    }

    It "Runs with limited (non-elevated) privileges" {
        $Script:EnableBlock.Contains('RunLevel Limited') | Should -BeTrue
    }

    It "Registers task with Register-ScheduledTask" {
        $Script:EnableBlock.Contains('Register-ScheduledTask') | Should -BeTrue
    }

    It "Logs the auto-start enablement" {
        $Script:EnableBlock.Contains('Write-RnsLog') | Should -BeTrue
        $Script:EnableBlock.Contains('Enabled rnsd auto-start') | Should -BeTrue
    }
}

Describe "Autostart: Disable-RnsdAutoStart" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Disable-RnsdAutoStart')
        $fnEnd = $Script:ServicesSource.IndexOf("`nfunction ", $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $Script:DisableBlock = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Uses same task name as Enable" {
        $Script:DisableBlock.Contains('RNS_rnsd_autostart') | Should -BeTrue
    }

    It "Checks if task exists before removing" {
        $Script:DisableBlock.Contains('Get-ScheduledTask') | Should -BeTrue
    }

    It "Unregisters without confirmation prompt" {
        $Script:DisableBlock.Contains('Unregister-ScheduledTask') | Should -BeTrue
        $Script:DisableBlock.Contains('-Confirm:$false') | Should -BeTrue
    }

    It "Reports when no task found" {
        $Script:DisableBlock.Contains('No auto-start task found') | Should -BeTrue
    }

    It "Logs the auto-start disablement" {
        $Script:DisableBlock.Contains('Write-RnsLog') | Should -BeTrue
        $Script:DisableBlock.Contains('Disabled rnsd auto-start') | Should -BeTrue
    }
}

# ---------------------------------------------------------
# RNS001: Command Safety (No Eval)
# ---------------------------------------------------------
Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:ServicesSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:ServicesSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }

    It "AST contains no Invoke-Expression commands" {
        $iexCmds = $Script:ServicesAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-Expression'
        }, $true)
        $iexCmds.Count | Should -Be 0
    }
}

# ---------------------------------------------------------
# Menu Structure
# ---------------------------------------------------------
Describe "Service Menu Structure" {

    BeforeAll {
        $fnIdx = $Script:ServicesSource.IndexOf('function Show-ServiceMenu')
        $Script:MenuBlock = $Script:ServicesSource.Substring($fnIdx)
    }

    It "Menu uses while loop (not recursive)" {
        $Script:MenuBlock.Contains('while ($true)') | Should -BeTrue
    }

    It "Menu shows rnsd running/stopped status" {
        $Script:MenuBlock.Contains('PID') | Should -BeTrue
        $Script:MenuBlock.Contains('Stopped') | Should -BeTrue
    }

    It "Menu has Daemon Control section" {
        $Script:MenuBlock.Contains('Daemon Control') | Should -BeTrue
    }

    It "Menu has Network Tools section" {
        $Script:MenuBlock.Contains('Network Tools') | Should -BeTrue
    }

    It "Menu has Identity & Boot section" {
        $Script:MenuBlock.Contains('Identity & Boot') | Should -BeTrue
    }

    It "Menu wires key options to correct functions" {
        # Spot-check a few representative options rather than all 12
        $Script:MenuBlock.Contains('Start-RNSDaemon') | Should -BeTrue
        $Script:MenuBlock.Contains('Stop-RNSDaemon') | Should -BeTrue
        $Script:MenuBlock.Contains('Show-Status') | Should -BeTrue
        $Script:MenuBlock.Contains('Invoke-NetworkTool') | Should -BeTrue
        $Script:MenuBlock.Contains('Invoke-IdentityManagement') | Should -BeTrue
        $Script:MenuBlock.Contains('Enable-RnsdAutoStart') | Should -BeTrue
        $Script:MenuBlock.Contains('Disable-RnsdAutoStart') | Should -BeTrue
    }

    It "Menu has back option (0)" {
        $Script:MenuBlock.Contains('"0"') | Should -BeTrue
        $Script:MenuBlock.Contains('return') | Should -BeTrue
    }

    It "Menu handles invalid input gracefully" {
        $Script:MenuBlock.Contains('Invalid option') | Should -BeTrue
    }
}
