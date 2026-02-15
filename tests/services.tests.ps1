#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/services.ps1 — Service management, autostart, network tools
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: daemon control, autostart (Task Scheduler), network tool dispatch,
    identity management, file transfer, remote command, menu structure
#>

BeforeAll {
    $Script:ServicesSource = Get-Content -Path "$PSScriptRoot/../pwsh/services.ps1" -Raw

    $Script:ServicesAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:ServicesSource, [ref]$null, [ref]$null
    )
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "Show-Status function exists" {
        $Script:ServicesSource | Should -Match 'function Show-Status'
    }

    It "Start-RNSDaemon function exists" {
        $Script:ServicesSource | Should -Match 'function Start-RNSDaemon'
    }

    It "Stop-RNSDaemon function exists" {
        $Script:ServicesSource | Should -Match 'function Stop-RNSDaemon'
    }

    It "Invoke-NetworkTool function exists" {
        $Script:ServicesSource | Should -Match 'function Invoke-NetworkTool'
    }

    It "Invoke-IdentityManagement function exists" {
        $Script:ServicesSource | Should -Match 'function Invoke-IdentityManagement'
    }

    It "Invoke-FileTransfer function exists" {
        $Script:ServicesSource | Should -Match 'function Invoke-FileTransfer'
    }

    It "Invoke-RemoteCommand function exists" {
        $Script:ServicesSource | Should -Match 'function Invoke-RemoteCommand'
    }

    It "Enable-RnsdAutoStart function exists" {
        $Script:ServicesSource | Should -Match 'function Enable-RnsdAutoStart'
    }

    It "Disable-RnsdAutoStart function exists" {
        $Script:ServicesSource | Should -Match 'function Disable-RnsdAutoStart'
    }

    It "Show-ServiceMenu function exists" {
        $Script:ServicesSource | Should -Match 'function Show-ServiceMenu'
    }

    It "services.ps1 has exactly 10 functions" {
        $functionCount = ([regex]::Matches(
            $Script:ServicesSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 10
    }
}

# ─────────────────────────────────────────────────────────────
# Daemon Control — Start-RNSDaemon
# ─────────────────────────────────────────────────────────────
Describe "Daemon Control: Start-RNSDaemon" {

    It "Start-RNSDaemon uses SupportsShouldProcess" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Start-RNSDaemon')
        $fnIdx | Should -BeGreaterOrEqual 0
        $cbIdx = $Script:ServicesSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
        $cbIdx | Should -BeGreaterThan $fnIdx
        ($cbIdx - $fnIdx) | Should -BeLessThan 100
    }

    It "Checks if rnsd is already running before starting" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Start-RNSDaemon')
        $block = $Script:ServicesSource.Substring($fnIdx, 400)
        $block | Should -Match 'Get-Process.*rnsd'
        $block | Should -Match 'already running'
    }

    It "Uses Start-Process with --daemon argument" {
        $Script:ServicesSource | Should -Match 'Start-Process.*rnsd.*--daemon'
    }

    It "Waits after starting for daemon to initialize" {
        $Script:ServicesSource | Should -Match 'Start-Sleep.*2'
    }

    It "Verifies daemon started after launch" {
        # After Start-Process there should be a Get-Process check
        $startIdx = $Script:ServicesSource.IndexOf('Start-Process')
        $verifyIdx = $Script:ServicesSource.IndexOf('started successfully', $startIdx)
        $verifyIdx | Should -BeGreaterThan $startIdx
    }

    It "Reports error if daemon fails to start" {
        $Script:ServicesSource | Should -Match 'failed to start'
    }
}

# ─────────────────────────────────────────────────────────────
# Daemon Control — Stop-RNSDaemon
# ─────────────────────────────────────────────────────────────
Describe "Daemon Control: Stop-RNSDaemon" {

    It "Stop-RNSDaemon uses SupportsShouldProcess" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Stop-RNSDaemon')
        $fnIdx | Should -BeGreaterOrEqual 0
        $cbIdx = $Script:ServicesSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
        $cbIdx | Should -BeGreaterThan $fnIdx
        ($cbIdx - $fnIdx) | Should -BeLessThan 100
    }

    It "Checks if rnsd is running before stopping" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Stop-RNSDaemon')
        $block = $Script:ServicesSource.Substring($fnIdx, 300)
        $block | Should -Match 'Get-Process.*rnsd'
    }

    It "Reports when rnsd is not running" {
        $Script:ServicesSource | Should -Match 'rnsd is not running'
    }

    It "Uses Stop-Process to terminate daemon" {
        $Script:ServicesSource | Should -Match 'Stop-Process.*rnsd.*Force'
    }

    It "Verifies daemon stopped after termination" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Stop-RNSDaemon')
        $fnEnd = $Script:ServicesSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $block = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'daemon stopped'
    }
}

# ─────────────────────────────────────────────────────────────
# Daemon Control — Restart
# ─────────────────────────────────────────────────────────────
Describe "Daemon Control: Restart" {

    It "Menu option 3 calls Stop then Start" {
        $Script:ServicesSource | Should -Match '"3".*Stop-RNSDaemon.*Start-RNSDaemon'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-Status
# ─────────────────────────────────────────────────────────────
Describe "Show-Status" {

    It "Displays rnsd process status" {
        $Script:ServicesSource | Should -Match 'Get-Process.*rnsd'
    }

    It "Shows installed component versions via pip" {
        $Script:ServicesSource | Should -Match 'pip show'
    }

    It "Checks rns, lxmf, and nomadnet packages" {
        $Script:ServicesSource | Should -Match '"rns".*"lxmf".*"nomadnet"'
    }

    It "Shows rnstatus output when available" {
        $Script:ServicesSource | Should -Match 'Get-Command rnstatus'
    }
}

# ─────────────────────────────────────────────────────────────
# Network Tool Dispatch
# ─────────────────────────────────────────────────────────────
Describe "Network Tool Dispatch: Invoke-NetworkTool" {

    It "Validates tool availability before execution" {
        $Script:ServicesSource | Should -Match 'Get-Command \$Tool'
    }

    It "Reports error for missing tools" {
        $Script:ServicesSource | Should -Match 'not installed.*Install RNS first'
    }

    It "Handles rnstatus tool" {
        $Script:ServicesSource | Should -Match '"rnstatus".*rnstatus'
    }

    It "Handles rnpath tool with -t flag" {
        $Script:ServicesSource | Should -Match '"rnpath".*rnpath -t'
    }

    It "Handles rnprobe with user-supplied destination" {
        $Script:ServicesSource | Should -Match '"rnprobe".*Read-Host.*destination'
    }
}

# ─────────────────────────────────────────────────────────────
# Identity Management
# ─────────────────────────────────────────────────────────────
Describe "Identity Management: Invoke-IdentityManagement" {

    It "Checks rnid availability" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Invoke-IdentityManagement')
        $block = $Script:ServicesSource.Substring($fnIdx, 300)
        $block | Should -Match 'Get-Command rnid'
    }

    It "Offers show identity hash option" {
        $Script:ServicesSource | Should -Match 'Show identity hash'
    }

    It "Offers generate new identity option" {
        $Script:ServicesSource | Should -Match 'Generate new identity'
    }

    It "Offers view identity file location option" {
        $Script:ServicesSource | Should -Match 'View identity file location'
    }

    It "Stores identities in .reticulum/identities directory" {
        $Script:ServicesSource | Should -Match '\.reticulum.*identities'
    }

    It "Creates identities directory if missing" {
        $Script:ServicesSource | Should -Match 'New-Item.*Directory.*identityDir'
    }

    It "Uses rnid --generate for new identities" {
        $Script:ServicesSource | Should -Match 'rnid --generate'
    }
}

# ─────────────────────────────────────────────────────────────
# File Transfer
# ─────────────────────────────────────────────────────────────
Describe "File Transfer: Invoke-FileTransfer" {

    It "Checks rncp availability" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Invoke-FileTransfer')
        $block = $Script:ServicesSource.Substring($fnIdx, 200)
        $block | Should -Match 'Get-Command rncp'
    }

    It "Validates file exists before sending" {
        $Script:ServicesSource | Should -Match 'Test-Path \$filePath'
    }

    It "Reports error for missing files" {
        $Script:ServicesSource | Should -Match 'File not found'
    }

    It "Offers listen mode for incoming transfers" {
        $Script:ServicesSource | Should -Match 'rncp --listen'
    }
}

# ─────────────────────────────────────────────────────────────
# Remote Command
# ─────────────────────────────────────────────────────────────
Describe "Remote Command: Invoke-RemoteCommand" {

    It "Checks rnx availability" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Invoke-RemoteCommand')
        $block = $Script:ServicesSource.Substring($fnIdx, 200)
        $block | Should -Match 'Get-Command rnx'
    }

    It "Requires destination hash" {
        $Script:ServicesSource | Should -Match 'No destination specified'
    }
}

# ─────────────────────────────────────────────────────────────
# Autostart via Task Scheduler
# ─────────────────────────────────────────────────────────────
Describe "Autostart: Enable-RnsdAutoStart" {

    It "Verifies rnsd is installed before creating task" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Enable-RnsdAutoStart')
        $block = $Script:ServicesSource.Substring($fnIdx, 300)
        $block | Should -Match 'Get-Command rnsd'
    }

    It "Uses consistent task name 'RNS_rnsd_autostart'" {
        $Script:ServicesSource | Should -Match 'RNS_rnsd_autostart'
    }

    It "Checks for existing scheduled task before creating" {
        $Script:ServicesSource | Should -Match 'Get-ScheduledTask.*TaskName.*taskName'
    }

    It "Asks confirmation before replacing existing task" {
        $Script:ServicesSource | Should -Match 'Replace existing task'
    }

    It "Unregisters old task before creating replacement" {
        $Script:ServicesSource | Should -Match 'Unregister-ScheduledTask.*taskName.*Confirm:\$false'
    }

    It "Creates task action with rnsd --daemon" {
        $Script:ServicesSource | Should -Match 'New-ScheduledTaskAction.*rnsdPath.*--daemon'
    }

    It "Uses AtLogOn trigger" {
        $Script:ServicesSource | Should -Match 'New-ScheduledTaskTrigger.*AtLogOn'
    }

    It "Runs with limited (non-elevated) privileges" {
        $Script:ServicesSource | Should -Match 'RunLevel Limited'
    }

    It "Registers task with Register-ScheduledTask" {
        $Script:ServicesSource | Should -Match 'Register-ScheduledTask'
    }

    It "Logs the auto-start enablement" {
        $Script:ServicesSource | Should -Match 'Write-RnsLog.*Enabled rnsd auto-start'
    }
}

Describe "Autostart: Disable-RnsdAutoStart" {

    It "Uses same task name as Enable" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Disable-RnsdAutoStart')
        $block = $Script:ServicesSource.Substring($fnIdx, 300)
        $block | Should -Match 'RNS_rnsd_autostart'
    }

    It "Checks if task exists before removing" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Disable-RnsdAutoStart')
        $block = $Script:ServicesSource.Substring($fnIdx, 300)
        $block | Should -Match 'Get-ScheduledTask'
    }

    It "Unregisters without confirmation prompt" {
        $fnIdx = $Script:ServicesSource.IndexOf('function Disable-RnsdAutoStart')
        $fnEnd = $Script:ServicesSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:ServicesSource.Length }
        $block = $Script:ServicesSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Unregister-ScheduledTask.*Confirm:\$false'
    }

    It "Reports when no task found" {
        $Script:ServicesSource | Should -Match 'No auto-start task found'
    }

    It "Logs the auto-start disablement" {
        $Script:ServicesSource | Should -Match 'Write-RnsLog.*Disabled rnsd auto-start'
    }
}

# ─────────────────────────────────────────────────────────────
# RNS001: Command Safety (No Eval)
# ─────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────
# Menu Structure
# ─────────────────────────────────────────────────────────────
Describe "Service Menu Structure" {

    It "Menu uses while loop (not recursive)" {
        $Script:ServicesSource | Should -Match 'while\s*\(\$true\)'
    }

    It "Menu has back option (0)" {
        $Script:ServicesSource | Should -Match '"0".*return'
    }

    It "Menu shows rnsd running/stopped status" {
        $Script:ServicesSource | Should -Match 'Running.*PID'
        $Script:ServicesSource | Should -Match 'Stopped'
    }

    It "Menu has Daemon Control section" {
        $Script:ServicesSource | Should -Match 'Daemon Control'
    }

    It "Menu has Network Tools section" {
        $Script:ServicesSource | Should -Match 'Network Tools'
    }

    It "Menu has Identity & Boot section" {
        $Script:ServicesSource | Should -Match 'Identity & Boot'
    }

    It "Menu offers all 12 options" {
        $Script:ServicesSource | Should -Match '"1".*Start-RNSDaemon'
        $Script:ServicesSource | Should -Match '"2".*Stop-RNSDaemon'
        $Script:ServicesSource | Should -Match '"3".*Stop-RNSDaemon.*Start-RNSDaemon'
        $Script:ServicesSource | Should -Match '"4".*Show-Status'
        $Script:ServicesSource | Should -Match '"5".*Invoke-NetworkTool.*rnstatus'
        $Script:ServicesSource | Should -Match '"6".*Invoke-NetworkTool.*rnpath'
        $Script:ServicesSource | Should -Match '"7".*Invoke-NetworkTool.*rnprobe'
        $Script:ServicesSource | Should -Match '"8".*Invoke-FileTransfer'
        $Script:ServicesSource | Should -Match '"9".*Invoke-RemoteCommand'
        $Script:ServicesSource | Should -Match '"10".*Invoke-IdentityManagement'
        $Script:ServicesSource | Should -Match '"11".*Enable-RnsdAutoStart'
        $Script:ServicesSource | Should -Match '"12".*Disable-RnsdAutoStart'
    }

    It "Menu handles invalid input gracefully" {
        $Script:ServicesSource | Should -Match 'default.*Invalid option'
    }
}
