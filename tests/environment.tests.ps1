#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/environment.ps1 — WSL, Python, pip detection
.NOTES
    Covers: Test-WSL, Get-WSLDistribution, Test-Python, Test-Pip
#>

BeforeAll {
    $Script:EnvSource = Get-Content -Path "$PSScriptRoot/../pwsh/environment.ps1" -Raw

    $Script:EnvAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:EnvSource, [ref]$null, [ref]$null
    )
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "Test-WSL function exists" {
        $Script:EnvSource | Should -Match 'function Test-WSL'
    }

    It "Get-WSLDistribution function exists" {
        $Script:EnvSource | Should -Match 'function Get-WSLDistribution'
    }

    It "Test-Python function exists" {
        $Script:EnvSource | Should -Match 'function Test-Python'
    }

    It "Test-Pip function exists" {
        $Script:EnvSource | Should -Match 'function Test-Pip'
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

# ─────────────────────────────────────────────────────────────
# Test-WSL
# ─────────────────────────────────────────────────────────────
Describe "Test-WSL" {

    It "Checks wsl command availability" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-WSL')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command wsl'
    }

    It "Runs wsl --list --quiet to verify functionality" {
        $Script:EnvSource | Should -Match 'wsl --list --quiet'
    }

    It "Returns boolean true when WSL is functional" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-WSL')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$true'
    }

    It "Returns boolean false when WSL unavailable" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-WSL')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$false'
    }

    It "Handles exceptions gracefully" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-WSL')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'catch'
    }
}

# ─────────────────────────────────────────────────────────────
# Get-WSLDistribution
# ─────────────────────────────────────────────────────────────
Describe "Get-WSLDistribution" {

    It "Calls Test-WSL before enumerating" {
        $fnIdx = $Script:EnvSource.IndexOf('function Get-WSLDistribution')
        $block = $Script:EnvSource.Substring($fnIdx, 200)
        $block | Should -Match 'Test-WSL'
    }

    It "Returns empty array when WSL unavailable" {
        $Script:EnvSource | Should -Match 'return @\(\)'
    }

    It "Uses wsl --list --quiet to get distributions" {
        $fnIdx = $Script:EnvSource.IndexOf('function Get-WSLDistribution')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'wsl --list --quiet'
    }

    It "Filters out empty entries" {
        $Script:EnvSource | Should -Match 'Where-Object.*\$_.*Trim'
    }
}

# ─────────────────────────────────────────────────────────────
# Test-Python
# ─────────────────────────────────────────────────────────────
Describe "Test-Python" {

    It "Checks for python command first" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Python')
        $block = $Script:EnvSource.Substring($fnIdx, 200)
        $block | Should -Match 'Get-Command python '
    }

    It "Falls back to python3" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Python')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command python3'
    }

    It "Runs --version to get Python version" {
        $Script:EnvSource | Should -Match '\$python\.Source --version'
    }

    It "Returns true when Python found" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Python')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$true'
    }

    It "Returns false when Python not found" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Python')
        $fnEnd = $Script:EnvSource.IndexOf('function', $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:EnvSource.Length }
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$false'
    }

    It "Reports Python not found as error" {
        $Script:EnvSource | Should -Match 'Python not found in PATH'
    }
}

# ─────────────────────────────────────────────────────────────
# Test-Pip
# ─────────────────────────────────────────────────────────────
Describe "Test-Pip" {

    It "Checks for pip command first" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Pip')
        $block = $Script:EnvSource.Substring($fnIdx, 200)
        $block | Should -Match 'Get-Command pip '
    }

    It "Falls back to pip3" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Pip')
        $fnEnd = $Script:EnvSource.Length
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command pip3'
    }

    It "Runs --version to get pip version" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Pip')
        $fnEnd = $Script:EnvSource.Length
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match '\$pip\.Source --version'
    }

    It "Returns true when pip found" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Pip')
        $fnEnd = $Script:EnvSource.Length
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$true'
    }

    It "Returns false when pip not found" {
        $fnIdx = $Script:EnvSource.IndexOf('function Test-Pip')
        $fnEnd = $Script:EnvSource.Length
        $block = $Script:EnvSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$false'
    }

    It "Reports pip not found as error" {
        $Script:EnvSource | Should -Match 'pip not found'
    }
}

# ─────────────────────────────────────────────────────────────
# RNS001: Command Safety (No Eval)
# ─────────────────────────────────────────────────────────────
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
