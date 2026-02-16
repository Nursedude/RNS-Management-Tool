#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/environment.ps1 — WSL, Python, pip detection
.NOTES
    Covers: Test-WSL, Get-WSLDistribution, Test-Python, Test-Pip.
    Uses .Contains() for literal string checks to avoid regex/source-text mismatch.
#>

BeforeAll {
    $Script:EnvSource = Get-Content -Path "$PSScriptRoot/../pwsh/environment.ps1" -Raw

    $Script:EnvAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:EnvSource, [ref]$null, [ref]$null
    )
}

Describe "Function Existence" {

    It "All 4 environment functions exist" {
        $Script:EnvSource.Contains('function Test-WSL') | Should -BeTrue
        $Script:EnvSource.Contains('function Get-WSLDistribution') | Should -BeTrue
        $Script:EnvSource.Contains('function Test-Python') | Should -BeTrue
        $Script:EnvSource.Contains('function Test-Pip') | Should -BeTrue
    }

    It "environment.ps1 has exactly 4 functions" {
        $functionCount = ([regex]::Matches(
            $Script:EnvSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 4
    }
}

Describe "Test-WSL" {

    BeforeAll {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-WSL')
        $fnEnd = $Script:EnvSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $Script:WslBlock = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks wsl command availability" {
        $Script:WslBlock.Contains('Get-Command wsl') | Should -BeTrue
    }

    It "Runs wsl --list --quiet to verify functionality" {
        $Script:WslBlock.Contains('wsl --list --quiet') | Should -BeTrue
    }

    It "Returns boolean true/false" {
        $Script:WslBlock.Contains('return $true') | Should -BeTrue
        $Script:WslBlock.Contains('return $false') | Should -BeTrue
    }

    It "Handles exceptions gracefully" {
        $Script:WslBlock.Contains('catch') | Should -BeTrue
    }
}

Describe "Get-WSLDistribution" {

    BeforeAll {
        $fnIdx = $Script:EnvSource.IndexOf('function Get-WSLDistribution')
        $fnEnd = $Script:EnvSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $Script:WslDistBlock = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Calls Test-WSL before enumerating" {
        $Script:WslDistBlock.Contains('Test-WSL') | Should -BeTrue
    }

    It "Returns empty array when WSL unavailable" {
        $Script:EnvSource.Contains('return @()') | Should -BeTrue
    }

    It "Uses wsl --list --quiet to get distributions" {
        $Script:WslDistBlock.Contains('wsl --list --quiet') | Should -BeTrue
    }

    It "Filters out empty entries" {
        $Script:EnvSource.Contains('Trim()') | Should -BeTrue
    }
}

Describe "Test-Python" {

    BeforeAll {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Python')
        $fnEnd = $Script:EnvSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $Script:PythonBlock = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks for python and python3 commands" {
        $Script:PythonBlock.Contains('Get-Command python ') | Should -BeTrue
        $Script:PythonBlock.Contains('Get-Command python3') | Should -BeTrue
    }

    It "Runs --version to get Python version" {
        $Script:EnvSource.Contains('$python.Source --version') | Should -BeTrue
    }

    It "Returns boolean true/false" {
        $Script:PythonBlock.Contains('return $true') | Should -BeTrue
        $Script:PythonBlock.Contains('return $false') | Should -BeTrue
    }

    It "Reports Python not found as error" {
        $Script:EnvSource.Contains('Python not found in PATH') | Should -BeTrue
    }
}

Describe "Test-Pip" {

    BeforeAll {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Pip')
        $Script:PipBlock = $Script:EnvSource.Substring($fnIdx)
    }

    It "Checks for pip and pip3 commands" {
        $Script:PipBlock.Contains('Get-Command pip ') | Should -BeTrue
        $Script:PipBlock.Contains('Get-Command pip3') | Should -BeTrue
    }

    It "Runs --version to get pip version" {
        $Script:PipBlock.Contains('$pip.Source --version') | Should -BeTrue
    }

    It "Returns boolean true/false" {
        $Script:PipBlock.Contains('return $true') | Should -BeTrue
        $Script:PipBlock.Contains('return $false') | Should -BeTrue
    }

    It "Reports pip not found as error" {
        $Script:EnvSource.Contains('pip not found') | Should -BeTrue
    }
}

Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:EnvSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:EnvSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }

    It "AST contains no Invoke-Expression commands" {
        $iexCmds = $Script:EnvAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-Expression'
        }, $true)
        $iexCmds.Count | Should -Be 0
    }
}
