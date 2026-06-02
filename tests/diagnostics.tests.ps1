#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/diagnostics.ps1 — 7-step system diagnostics
.NOTES
    Covers: 7-step diagnostic pipeline, issue/warning counters,
    environment checks, RNS tool detection, config validation,
    service health, network/USB, summary with recommendations.
    Uses .Contains() for literal string checks to avoid regex/source-text mismatch.
#>

BeforeAll {
    $Script:DiagSource = Get-Content -Path "$PSScriptRoot/../pwsh/diagnostics.ps1" -Raw

    $Script:DiagAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:DiagSource, [ref]$null, [ref]$null
    )
}

Describe "Function Existence" {

    It "All 8 diagnostic functions exist" {
        $Script:DiagSource.Contains('function Invoke-DiagCheckEnvironment') | Should -BeTrue
        $Script:DiagSource.Contains('function Invoke-DiagCheckRnsTool') | Should -BeTrue
        $Script:DiagSource.Contains('function Invoke-DiagCheckConfiguration') | Should -BeTrue
        $Script:DiagSource.Contains('function Invoke-DiagCheckService') | Should -BeTrue
        $Script:DiagSource.Contains('function Invoke-DiagCheckNetwork') | Should -BeTrue
        $Script:DiagSource.Contains('function Invoke-DiagRnsDoctor') | Should -BeTrue
        $Script:DiagSource.Contains('function Invoke-DiagReportSummary') | Should -BeTrue
        $Script:DiagSource.Contains('function Show-Diagnostic') | Should -BeTrue
    }

    It "diagnostics.ps1 has exactly 8 functions" {
        $functionCount = ([regex]::Matches(
            $Script:DiagSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 8
    }
}

Describe "Diagnostic Counters" {

    It "Initializes DiagIssues and DiagWarnings counters" {
        $Script:DiagSource.Contains('$Script:DiagIssues = 0') | Should -BeTrue
        $Script:DiagSource.Contains('$Script:DiagWarnings = 0') | Should -BeTrue
    }

    It "Show-Diagnostic resets counters before running" {
        $fnIdx = $Script:DiagSource.IndexOf('function Show-Diagnostic')
        $block = $Script:DiagSource.Substring($fnIdx, 300)
        $block.Contains('$Script:DiagIssues = 0') | Should -BeTrue
        $block.Contains('$Script:DiagWarnings = 0') | Should -BeTrue
    }
}

Describe "Step 1/7: Invoke-DiagCheckEnvironment" {

    BeforeAll {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckEnvironment')
        $fnEnd = $Script:DiagSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $Script:Step1Block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Displays step header" {
        $Script:DiagSource.Contains('Step 1/7') | Should -BeTrue
    }

    It "Shows platform and architecture info" {
        $Script:Step1Block.Contains('Platform') | Should -BeTrue
        $Script:Step1Block.Contains('Architecture') | Should -BeTrue
    }

    It "Checks admin status" {
        $Script:Step1Block.Contains('IsAdmin') | Should -BeTrue
    }

    It "Checks Python and pip availability" {
        $Script:Step1Block.Contains('Get-Command python') | Should -BeTrue
        $Script:Step1Block.Contains('Get-Command pip') | Should -BeTrue
    }

    It "Provides fix hint when Python missing" {
        $Script:DiagSource.Contains('Install Python from python.org') | Should -BeTrue
    }

    It "Increments issue counter for missing prerequisites" {
        $Script:Step1Block.Contains('$Script:DiagIssues++') | Should -BeTrue
    }
}

Describe "Step 2/7: Invoke-DiagCheckRnsTool" {

    It "Checks all 8 RNS tools" {
        $Script:DiagSource.Contains('"rnsd"') | Should -BeTrue
        $Script:DiagSource.Contains('"rnstatus"') | Should -BeTrue
        $Script:DiagSource.Contains('"rnpath"') | Should -BeTrue
        $Script:DiagSource.Contains('"rnprobe"') | Should -BeTrue
        $Script:DiagSource.Contains('"rncp"') | Should -BeTrue
        $Script:DiagSource.Contains('"rnx"') | Should -BeTrue
        $Script:DiagSource.Contains('"rnid"') | Should -BeTrue
        $Script:DiagSource.Contains('"rnodeconf"') | Should -BeTrue
    }

    It "Shows install hint for missing tools" {
        $Script:DiagSource.Contains('pip install rns') | Should -BeTrue
    }

    It "Uses Get-Command for tool detection" {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckRnsTool')
        $fnEnd = $Script:DiagSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block.Contains('Get-Command $tool.Name') | Should -BeTrue
    }
}

Describe "Step 3/7: Invoke-DiagCheckConfiguration" {

    BeforeAll {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckConfiguration')
        $fnEnd = $Script:DiagSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $Script:Step3Block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks .reticulum config directory" {
        $Script:Step3Block.Contains('.reticulum') | Should -BeTrue
        $Script:Step3Block.Contains('configFile') | Should -BeTrue
    }

    It "Validates config file is not empty" {
        $Script:DiagSource.Contains('-lt 10') | Should -BeTrue
    }

    It "Checks for disabled interfaces" {
        $Script:DiagSource.Contains('interface_enabled = false') | Should -BeTrue
    }

    It "Provides fix hint for missing config" {
        $Script:DiagSource.Contains('rnsd --daemon') | Should -BeTrue
        $Script:DiagSource.Contains('create default config') | Should -BeTrue
    }
}

Describe "Step 4/7: Invoke-DiagCheckService" {

    BeforeAll {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagCheckService')
        $fnEnd = $Script:DiagSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $Script:Step4Block = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks rnsd process" {
        $Script:Step4Block.Contains('Get-Process') | Should -BeTrue
        $Script:Step4Block.Contains('rnsd') | Should -BeTrue
    }

    It "Shows uptime in appropriate units" {
        $Script:DiagSource.Contains('TotalSeconds') | Should -BeTrue
        $Script:DiagSource.Contains('TotalMinutes') | Should -BeTrue
        $Script:DiagSource.Contains('TotalHours') | Should -BeTrue
    }

    It "Checks WSL rnsd when WSL available" {
        $Script:DiagSource.Contains('wsl pgrep') | Should -BeTrue
    }
}

Describe "Step 5/7: Invoke-DiagCheckNetwork" {

    It "Enumerates network adapters" {
        $Script:DiagSource.Contains('Get-NetAdapter') | Should -BeTrue
    }

    It "Checks USB serial devices via CIM" {
        $Script:DiagSource.Contains('Get-CimInstance') | Should -BeTrue
        $Script:DiagSource.Contains('Win32_PnPEntity') | Should -BeTrue
    }

    It "Detects common USB-serial chipsets" {
        $Script:DiagSource.Contains('CH340') | Should -BeTrue
        $Script:DiagSource.Contains('CP210') | Should -BeTrue
        $Script:DiagSource.Contains('FTDI') | Should -BeTrue
    }

    It "Falls back to SerialPort.GetPortNames" {
        $Script:DiagSource.Contains('SerialPort') | Should -BeTrue
        $Script:DiagSource.Contains('GetPortNames') | Should -BeTrue
    }
}

Describe "Step 6/7: Invoke-DiagRnsDoctor" {

    BeforeAll {
        $fnIdx = $Script:DiagSource.IndexOf('function Invoke-DiagRnsDoctor')
        $fnEnd = $Script:DiagSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:DiagSource.Length }
        $Script:DoctorBlock = $Script:DiagSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Displays step header" {
        $Script:DiagSource.Contains('Step 6/7') | Should -BeTrue
    }

    It "Detects the Microsoft Store python alias stub" {
        $Script:DoctorBlock.Contains('WindowsApps') | Should -BeTrue
        $Script:DoctorBlock.Contains('App execution aliases') | Should -BeTrue
    }

    It "Imports RNS to find the live version and path" {
        $Script:DoctorBlock.Contains('import RNS') | Should -BeTrue
        $Script:DoctorBlock.Contains('RNS.__file__') | Should -BeTrue
    }

    It "Flags pip-vs-import version mismatch (shadowed install)" {
        $Script:DoctorBlock.Contains('Version mismatch') | Should -BeTrue
    }

    It "Flags rnsd not on PATH while RNS importable" {
        $Script:DoctorBlock.Contains('not on PATH') | Should -BeTrue
    }

    It "Checks the MeshChatX environment too" {
        $Script:DoctorBlock.Contains('reticulum-meshchatx') | Should -BeTrue
    }

    It "Increments warning or issue counters" {
        ($Script:DoctorBlock.Contains('$Script:DiagWarnings++') -or `
         $Script:DoctorBlock.Contains('$Script:DiagIssues++')) | Should -BeTrue
    }
}

Describe "Step 7/7: Invoke-DiagReportSummary" {

    It "Reports healthy when no issues" {
        $Script:DiagSource.Contains('All checks passed') | Should -BeTrue
    }

    It "Reports issue and warning counts" {
        $Script:DiagSource.Contains('issue(s) found') | Should -BeTrue
        $Script:DiagSource.Contains('warning(s) found') | Should -BeTrue
    }

    It "Provides recommended actions" {
        $Script:DiagSource.Contains('Recommended actions') | Should -BeTrue
    }

    It "Logs diagnostic results" {
        $Script:DiagSource.Contains('Diagnostics complete') | Should -BeTrue
    }
}

Describe "Show-Diagnostic: Orchestrator" {

    It "Runs all 7 diagnostic steps in order" {
        $fnIdx = $Script:DiagSource.IndexOf('function Show-Diagnostic')
        $block = $Script:DiagSource.Substring($fnIdx)

        $idx1 = $block.IndexOf('Invoke-DiagCheckEnvironment')
        $idx2 = $block.IndexOf('Invoke-DiagCheckRnsTool')
        $idx3 = $block.IndexOf('Invoke-DiagCheckConfiguration')
        $idx4 = $block.IndexOf('Invoke-DiagCheckService')
        $idx5 = $block.IndexOf('Invoke-DiagCheckNetwork')
        $idx6 = $block.IndexOf('Invoke-DiagRnsDoctor')
        $idx7 = $block.IndexOf('Invoke-DiagReportSummary')

        $idx1 | Should -BeGreaterThan 0
        $idx2 | Should -BeGreaterThan $idx1
        $idx3 | Should -BeGreaterThan $idx2
        $idx4 | Should -BeGreaterThan $idx3
        $idx5 | Should -BeGreaterThan $idx4
        $idx6 | Should -BeGreaterThan $idx5
        $idx7 | Should -BeGreaterThan $idx6
    }

    It "Describes running 7-step diagnostic" {
        $Script:DiagSource.Contains('7-step diagnostic') | Should -BeTrue
    }
}

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
