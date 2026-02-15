#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/diagnostics.ps1 — 6-step system diagnostics
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: 6-step diagnostic pipeline, issue/warning counters,
    environment checks, RNS tool detection, config validation,
    service health, network/USB, summary with recommendations
#>

BeforeAll {
    $Script:DiagSource = Get-Content -Path "$PSScriptRoot/../pwsh/diagnostics.ps1" -Raw

    $Script:DiagAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:DiagSource, [ref]$null, [ref]$null
    )
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "Invoke-DiagCheckEnvironment function exists" {
        $Script:DiagSource | Should -Match 'function Invoke-DiagCheckEnvironment'
    }

    It "Invoke-DiagCheckRnsTool function exists" {
        $Script:DiagSource | Should -Match 'function Invoke-DiagCheckRnsTool'
    }

    It "Invoke-DiagCheckConfiguration function exists" {
        $Script:DiagSource | Should -Match 'function Invoke-DiagCheckConfiguration'
    }

    It "Invoke-DiagCheckService function exists" {
        $Script:DiagSource | Should -Match 'function Invoke-DiagCheckService'
    }

    It "Invoke-DiagCheckNetwork function exists" {
        $Script:DiagSource | Should -Match 'function Invoke-DiagCheckNetwork'
    }

    It "Invoke-DiagReportSummary function exists" {
        $Script:DiagSource | Should -Match 'function Invoke-DiagReportSummary'
    }

    It "Show-Diagnostic function exists" {
        $Script:DiagSource | Should -Match 'function Show-Diagnostic'
    }

    It "diagnostics.ps1 has exactly 7 functions" {
        $functionCount = ([regex]::Matches(
            $Script:DiagSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 7
    }
}

# ─────────────────────────────────────────────────────────────
# Issue & Warning Counters
# ─────────────────────────────────────────────────────────────
Describe "Diagnostic Counters" {

    It "Initializes DiagIssues counter" {
        $Script:DiagSource | Should -Match '\$Script:DiagIssues\s*=\s*0'
    }

    It "Initializes DiagWarnings counter" {
        $Script:DiagSource | Should -Match '\$Script:DiagWarnings\s*=\s*0'
    }

    It "Show-Diagnostic resets counters before running" {
        $fnIdx = $Script:DiagSource.IndexOf('function Show-Diagnostic')
        $block = $Script:DiagSource.Substring($fnIdx, 300)
        $block | Should -Match '\$Script:DiagIssues = 0'
        $block | Should -Match '\$Script:DiagWarnings = 0'
    }
}

# ─────────────────────────────────────────────────────────────
# Step 1/6: Environment & Prerequisites
# ─────────────────────────────────────────────────────────────
Describe "Step 1/6: Invoke-DiagCheckEnvironment" {

    It "Displays step header" {
        $Script:DiagSource | Should -Match 'Step 1/6.*Environment.*Prerequisites'
    }

    It "Shows platform info" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckEnvironment')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Platform'
        $block | Should -Match 'Architecture'
    }

    It "Checks admin status" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckEnvironment')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'IsAdmin'
    }

    It "Checks Python availability" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckEnvironment')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command python'
    }

    It "Provides fix hint when Python missing" {
        $Script:DiagSource | Should -Match 'Fix.*Install Python from python\.org'
    }

    It "Increments issue counter for missing Python" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckEnvironment')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match '\$Script:DiagIssues\+\+'
    }

    It "Checks pip availability" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckEnvironment')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command pip'
    }

    It "Falls back to pip3 check" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckEnvironment')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command pip3'
    }
}

# ─────────────────────────────────────────────────────────────
# Step 2/6: RNS Tool Availability
# ─────────────────────────────────────────────────────────────
Describe "Step 2/6: Invoke-DiagCheckRnsTool" {

    It "Displays step header" {
        $Script:DiagSource | Should -Match 'Step 2/6.*RNS Tool Availability'
    }

    It "Checks all 8 RNS tools" {
        $Script:DiagSource | Should -Match '"rnsd"'
        $Script:DiagSource | Should -Match '"rnstatus"'
        $Script:DiagSource | Should -Match '"rnpath"'
        $Script:DiagSource | Should -Match '"rnprobe"'
        $Script:DiagSource | Should -Match '"rncp"'
        $Script:DiagSource | Should -Match '"rnx"'
        $Script:DiagSource | Should -Match '"rnid"'
        $Script:DiagSource | Should -Match '"rnodeconf"'
    }

    It "Shows install hint for missing tools" {
        $Script:DiagSource | Should -Match 'pip install rns'
    }

    It "Uses Get-Command for tool detection" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckRnsTool')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command \$tool\.Name'
    }

    It "Counts missing tools" {
        $Script:DiagSource | Should -Match '\$missing\+\+'
    }
}

# ─────────────────────────────────────────────────────────────
# Step 3/6: Configuration Validation
# ─────────────────────────────────────────────────────────────
Describe "Step 3/6: Invoke-DiagCheckConfiguration" {

    It "Displays step header" {
        $Script:DiagSource | Should -Match 'Step 3/6.*Configuration Validation'
    }

    It "Checks .reticulum/config file" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckConfiguration')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match '\.reticulum.*config'
    }

    It "Validates config file is not empty" {
        $Script:DiagSource | Should -Match 'configSize.*-lt 10'
    }

    It "Checks for disabled interfaces" {
        $Script:DiagSource | Should -Match 'interface_enabled = false'
    }

    It "Provides fix hint for missing config" {
        $Script:DiagSource | Should -Match "Fix.*rnsd --daemon.*create default config"
    }
}

# ─────────────────────────────────────────────────────────────
# Step 4/6: Service Health
# ─────────────────────────────────────────────────────────────
Describe "Step 4/6: Invoke-DiagCheckService" {

    It "Displays step header" {
        $Script:DiagSource | Should -Match 'Step 4/6.*Service Health'
    }

    It "Checks rnsd process" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckService')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Process.*rnsd'
    }

    It "Shows uptime for running rnsd" {
        $Script:DiagSource | Should -Match 'rnsdProcess\.StartTime'
    }

    It "Displays uptime in appropriate units (seconds, minutes, hours)" {
        $Script:DiagSource | Should -Match 'TotalSeconds'
        $Script:DiagSource | Should -Match 'TotalMinutes'
        $Script:DiagSource | Should -Match 'TotalHours'
    }

    It "Checks WSL rnsd when WSL available" {
        $Script:DiagSource | Should -Match 'wsl pgrep.*rnsd'
    }
}

# ─────────────────────────────────────────────────────────────
# Step 5/6: Network & Interfaces
# ─────────────────────────────────────────────────────────────
Describe "Step 5/6: Invoke-DiagCheckNetwork" {

    It "Displays step header" {
        $Script:DiagSource | Should -Match 'Step 5/6.*Network.*Interfaces'
    }

    It "Enumerates network adapters" {
        $Script:DiagSource | Should -Match 'Get-NetAdapter'
    }

    It "Filters for active adapters" {
        $Script:DiagSource | Should -Match 'Status.*Up'
    }

    It "Checks USB serial devices via CIM" {
        $Script:DiagSource | Should -Match 'Get-CimInstance.*Win32_PnPEntity'
    }

    It "Detects common USB-serial chipsets" {
        $Script:DiagSource | Should -Match 'USB|Serial|CH340|CP210|FTDI|Silicon Labs'
    }

    It "Falls back to SerialPort.GetPortNames" {
        $Script:DiagSource | Should -Match 'SerialPort.*GetPortNames'
    }

    It "Shows rnstatus output when available" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckNetwork')
        $fnEnd = $Script:DiagSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'rnstatus'
    }
}

# ─────────────────────────────────────────────────────────────
# Step 6/6: Summary & Recommendations
# ─────────────────────────────────────────────────────────────
Describe "Step 6/6: Invoke-DiagReportSummary" {

    It "Displays step header" {
        $Script:DiagSource | Should -Match 'Step 6/6.*Summary.*Recommendations'
    }

    It "Reports healthy when no issues or warnings" {
        $Script:DiagSource | Should -Match 'All checks passed.*system looks healthy'
    }

    It "Reports issue count" {
        $Script:DiagSource | Should -Match 'DiagIssues.*issue.*found'
    }

    It "Reports warning count" {
        $Script:DiagSource | Should -Match 'DiagWarnings.*warning.*found'
    }

    It "Provides recommended actions" {
        $Script:DiagSource | Should -Match 'Recommended actions'
    }

    It "Recommends installing Reticulum when rnsd missing" {
        $Script:DiagSource | Should -Match 'Install Reticulum.*option 1'
    }

    It "Recommends starting rnsd when not running" {
        $Script:DiagSource | Should -Match 'Start rnsd.*option 7'
    }

    It "Recommends creating config when missing" {
        $Script:DiagSource | Should -Match 'Create configuration.*rnsd --daemon'
    }

    It "Logs diagnostic results" {
        $Script:DiagSource | Should -Match 'Write-RnsLog.*Diagnostics complete.*issues.*warnings'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-Diagnostic (orchestrator)
# ─────────────────────────────────────────────────────────────
Describe "Show-Diagnostic: Orchestrator" {

    It "Runs all 6 diagnostic steps in order" {
        $fnIdx = $Script:DiagSource.IndexOf('function Show-Diagnostic')
        $fnEnd = $Script:DiagSource.Length
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)

        $idx1 = $block.IndexOf('Invoke-DiagCheckEnvironment')
        $idx2 = $block.IndexOf('Invoke-DiagCheckRnsTool')
        $idx3 = $block.IndexOf('Invoke-DiagCheckConfiguration')
        $idx4 = $block.IndexOf('Invoke-DiagCheckService')
        $idx5 = $block.IndexOf('Invoke-DiagCheckNetwork')
        $idx6 = $block.IndexOf('Invoke-DiagReportSummary')

        $idx1 | Should -BeGreaterThan 0
        $idx2 | Should -BeGreaterThan $idx1
        $idx3 | Should -BeGreaterThan $idx2
        $idx4 | Should -BeGreaterThan $idx3
        $idx5 | Should -BeGreaterThan $idx4
        $idx6 | Should -BeGreaterThan $idx5
    }

    It "Describes running 6-step diagnostic" {
        $Script:DiagSource | Should -Match '6-step diagnostic'
    }
}

# ─────────────────────────────────────────────────────────────
# RNS001: Command Safety (No Eval)
# ─────────────────────────────────────────────────────────────
Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:DiagSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:DiagSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }

    It "AST contains no Invoke-Expression commands" {
        $iexCmds = $Script:DiagAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-Expression'
        }, $true)
        $iexCmds.Count | Should -Be 0
    }
}
