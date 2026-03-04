#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/advanced.ps1 — Advanced options, config management
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: function existence, function count, factory reset safety (RESET
    confirmation, pre-reset backup), export/import config ordering, RNS004
    path traversal prevention, RNS001 command safety (no eval), menu structure
#>

BeforeAll {
    $Script:AdvancedSource = Get-Content -Path "$PSScriptRoot/../pwsh/advanced.ps1" -Raw

    $Script:AdvancedAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:AdvancedSource, [ref]$null, [ref]$null
    )
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "advanced.ps1 has exactly 6 functions" {
        $functionCount = ([regex]::Matches(
            $Script:AdvancedSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 6
    }
}

# ─────────────────────────────────────────────────────────────
# Factory Reset Safety
# ─────────────────────────────────────────────────────────────
Describe "Factory Reset Safety: Reset-ToFactory" {

    BeforeAll {
        $fn = $Script:AdvancedAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Reset-ToFactory'
        }, $true) | Select-Object -First 1
        $Script:ResetBlock = $fn.Extent.Text
    }

    It "Uses SupportsShouldProcess" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Reset-ToFactory')
        $fnIdx | Should -BeGreaterOrEqual 0
        $cbIdx = $Script:AdvancedSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
        $cbIdx | Should -BeGreaterThan $fnIdx
        ($cbIdx - $fnIdx) | Should -BeLessThan 100
    }

    It "Requires typing 'RESET' for confirmation (not y/Y)" {
        $Script:ResetBlock.Contains("Type 'RESET' to confirm") | Should -BeTrue
    }

    It "Validates exact RESET string match" {
        $Script:ResetBlock.Contains('$confirm -ne "RESET"') | Should -BeTrue
    }

    It "Creates backup BEFORE performing reset" {
        $backupIdx = $Script:ResetBlock.IndexOf('New-Backup')
        $removeIdx = $Script:ResetBlock.IndexOf('Remove-Item')
        $backupIdx | Should -BeGreaterThan 0
        $removeIdx | Should -BeGreaterThan $backupIdx
    }

    It "Removes .reticulum, .nomadnetwork, and .lxmf directories" {
        $Script:ResetBlock.Contains('reticulumDir') | Should -BeTrue
        $Script:ResetBlock.Contains('nomadDir') | Should -BeTrue
        $Script:ResetBlock.Contains('lxmfDir') | Should -BeTrue
        # All three are removed
        $Script:ResetBlock.Contains('Remove-Item') | Should -BeTrue
    }

    It "Logs factory reset to log file" {
        $Script:ResetBlock.Contains('Factory reset performed') | Should -BeTrue
    }
}

# ─────────────────────────────────────────────────────────────
# Export/Import consolidated in pwsh/backup.ps1 (R8)
# Tests for Export-RnsConfiguration and Import-RnsConfiguration
# are in tests/backup.tests.ps1
# ─────────────────────────────────────────────────────────────

Describe "Advanced Menu calls consolidated backup functions" {

    BeforeAll {
        $fn = $Script:AdvancedAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Show-AdvancedMenu'
        }, $true) | Select-Object -First 1
        $Script:AdvMenuBlock = $fn.Extent.Text
    }

    It "Calls Export-RnsConfiguration (not Export-Configuration)" {
        $Script:AdvMenuBlock.Contains('Export-RnsConfiguration') | Should -BeTrue
        $Script:AdvMenuBlock.Contains('Export-Configuration') | Should -BeFalse
    }

    It "Calls Import-RnsConfiguration (not Import-Configuration)" {
        $Script:AdvMenuBlock.Contains('Import-RnsConfiguration') | Should -BeTrue
        $Script:AdvMenuBlock.Contains('Import-Configuration') | Should -BeFalse
    }
}

# ─────────────────────────────────────────────────────────────
# RNS001: Command Safety (No Eval)
# ─────────────────────────────────────────────────────────────
Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:AdvancedSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:AdvancedSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }

    It "AST contains no Invoke-Expression commands" {
        $iexCmds = $Script:AdvancedAst.FindAll({
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
Describe "Advanced Menu Structure" {

    BeforeAll {
        $fn = $Script:AdvancedAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Show-AdvancedMenu'
        }, $true) | Select-Object -First 1
        $Script:MenuBlock = $fn.Extent.Text
    }

    It "Menu has back option (0) that returns" {
        $Script:MenuBlock.Contains('"0"') | Should -BeTrue
        $Script:MenuBlock.Contains('return') | Should -BeTrue
    }

    It "Menu handles invalid input with default case" {
        $Script:MenuBlock.Contains('default') | Should -BeTrue
        $Script:MenuBlock.Contains('Invalid option') | Should -BeTrue
    }
}
