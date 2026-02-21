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

    It "advanced.ps1 has exactly 8 functions" {
        $functionCount = ([regex]::Matches(
            $Script:AdvancedSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 8
    }
}

# ─────────────────────────────────────────────────────────────
# Factory Reset Safety
# ─────────────────────────────────────────────────────────────
Describe "Factory Reset Safety: Reset-ToFactory" {

    BeforeAll {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Reset-ToFactory')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $Script:ResetBlock = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
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
# Import-Configuration (RNS004 path traversal)
# ─────────────────────────────────────────────────────────────
Describe "Import-Configuration: RNS004 Path Traversal Prevention" {

    BeforeAll {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Import-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $Script:ImportBlock = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Validates .zip extension" {
        $Script:ImportBlock.Contains('.zip') | Should -BeTrue
        $Script:ImportBlock.Contains('-notmatch') | Should -BeTrue
    }

    It "Uses ZipFile.OpenRead for archive validation" {
        $Script:ImportBlock.Contains('ZipFile') | Should -BeTrue
        $Script:ImportBlock.Contains('OpenRead') | Should -BeTrue
    }

    It "Checks for '..' path traversal in entries" {
        $Script:ImportBlock.Contains('hasInvalidPaths') | Should -BeTrue
        $Script:ImportBlock.Contains('entry.FullName') | Should -BeTrue
    }

    It "Checks for absolute paths starting with / and \" {
        $Script:ImportBlock.Contains("StartsWith('/')") | Should -BeTrue
        $Script:ImportBlock.Contains("StartsWith('\')") | Should -BeTrue
    }

    It "Disposes zip handle after validation" {
        $Script:ImportBlock.Contains('$zip.Dispose()') | Should -BeTrue
    }

    It "Logs security violations" {
        $Script:ImportBlock.Contains('SECURITY') | Should -BeTrue
        $Script:ImportBlock.Contains('invalid paths') | Should -BeTrue
    }

    It "Validates archive before extraction" {
        $validationIdx = $Script:ImportBlock.IndexOf('ZipFile')
        $expandIdx = $Script:ImportBlock.IndexOf('Expand-Archive')
        $validationIdx | Should -BeLessThan $expandIdx
    }

    It "Creates backup before import" {
        $backupIdx = $Script:ImportBlock.IndexOf('New-Backup')
        $expandIdx = $Script:ImportBlock.IndexOf('Expand-Archive')
        $backupIdx | Should -BeGreaterThan 0
        $expandIdx | Should -BeGreaterThan $backupIdx
    }

    It "Cleans up temp import directory" {
        $Script:ImportBlock.Contains('tempImport') | Should -BeTrue
        $Script:ImportBlock.Contains('Remove-Item') | Should -BeTrue
    }
}

# ─────────────────────────────────────────────────────────────
# Export-Configuration
# ─────────────────────────────────────────────────────────────
Describe "Export-Configuration" {

    BeforeAll {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Export-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $Script:ExportBlock = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Uses Compress-Archive for zip creation" {
        $Script:ExportBlock.Contains('Compress-Archive') | Should -BeTrue
    }

    It "Cleans up temp directory after export" {
        $Script:ExportBlock.Contains('tempExport') | Should -BeTrue
        $Script:ExportBlock.Contains('Remove-Item') | Should -BeTrue
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
        $fnIdx = $Script:AdvancedSource.IndexOf('function Show-AdvancedMenu')
        $Script:MenuBlock = $Script:AdvancedSource.Substring($fnIdx)
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
