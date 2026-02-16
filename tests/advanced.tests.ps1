#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/advanced.ps1 — Advanced options, config management
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: factory reset safety (RESET confirmation, pre-reset backup),
    export/import config, cache cleanup, update checks, menu structure
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

    It "Update-PythonPackage function exists" {
        $Script:AdvancedSource | Should -Match 'function Update-PythonPackage'
    }

    It "Clear-Cache function exists" {
        $Script:AdvancedSource | Should -Match 'function Clear-Cache'
    }

    It "Export-Configuration function exists" {
        $Script:AdvancedSource | Should -Match 'function Export-Configuration'
    }

    It "Import-Configuration function exists" {
        $Script:AdvancedSource | Should -Match 'function Import-Configuration'
    }

    It "Reset-ToFactory function exists" {
        $Script:AdvancedSource | Should -Match 'function Reset-ToFactory'
    }

    It "Show-Log function exists" {
        $Script:AdvancedSource | Should -Match 'function Show-Log'
    }

    It "Test-ToolUpdate function exists" {
        $Script:AdvancedSource | Should -Match 'function Test-ToolUpdate'
    }

    It "Show-AdvancedMenu function exists" {
        $Script:AdvancedSource | Should -Match 'function Show-AdvancedMenu'
    }

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

    It "Uses SupportsShouldProcess" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Reset-ToFactory')
        $fnIdx | Should -BeGreaterOrEqual 0
        $cbIdx = $Script:AdvancedSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
        $cbIdx | Should -BeGreaterThan $fnIdx
        ($cbIdx - $fnIdx) | Should -BeLessThan 100
    }

    It "Displays prominent WARNING banner" {
        $Script:AdvancedSource | Should -Match 'WARNING!'
    }

    It "Warning is displayed in red" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Reset-ToFactory')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'ForegroundColor Red'
    }

    It "Warns about identity and message loss" {
        $Script:AdvancedSource | Should -Match 'identities and messages will be LOST'
    }

    It "Lists directories that will be removed" {
        $Script:AdvancedSource | Should -Match '\.reticulum/'
        $Script:AdvancedSource | Should -Match '\.nomadnetwork/'
        $Script:AdvancedSource | Should -Match '\.lxmf/'
    }

    It "Requires typing 'RESET' for confirmation (not y/Y)" {
        $Script:AdvancedSource | Should -Match "Type 'RESET' to confirm"
    }

    It "Validates exact RESET string match" {
        $Script:AdvancedSource | Should -Match '\$confirm -ne "RESET"'
    }

    It "Reports cancellation when confirmation not received" {
        $Script:AdvancedSource | Should -Match 'Reset cancelled.*confirmation not received'
    }

    It "Creates backup BEFORE performing reset" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Reset-ToFactory')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $backupIdx = $block.IndexOf('New-Backup')
        $removeIdx = $block.IndexOf('Remove-Item')
        $backupIdx | Should -BeGreaterThan 0
        $removeIdx | Should -BeGreaterThan $backupIdx
    }

    It "Logs 'Creating final backup before reset'" {
        $Script:AdvancedSource | Should -Match 'Creating final backup before reset'
    }

    It "Removes .reticulum directory" {
        $Script:AdvancedSource | Should -Match 'Remove-Item.*reticulumDir.*Recurse.*Force'
    }

    It "Removes .nomadnetwork directory" {
        $Script:AdvancedSource | Should -Match 'Remove-Item.*nomadDir.*Recurse.*Force'
    }

    It "Removes .lxmf directory" {
        $Script:AdvancedSource | Should -Match 'Remove-Item.*lxmfDir.*Recurse.*Force'
    }

    It "Logs factory reset to log file" {
        $Script:AdvancedSource | Should -Match 'Factory reset performed.*all configurations removed'
    }

    It "Advises user how to create fresh config after reset" {
        $Script:AdvancedSource | Should -Match 'rnsd --daemon.*create fresh configuration'
    }
}

# ─────────────────────────────────────────────────────────────
# Update-PythonPackage
# ─────────────────────────────────────────────────────────────
Describe "Update-PythonPackage" {

    It "Uses SupportsShouldProcess" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Update-PythonPackage')
        $fnIdx | Should -BeGreaterOrEqual 0
        $cbIdx = $Script:AdvancedSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
        $cbIdx | Should -BeGreaterThan $fnIdx
        ($cbIdx - $fnIdx) | Should -BeLessThan 100
    }

    It "Requires confirmation before updating" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Update-PythonPackage')
        $block = $Script:AdvancedSource.Substring($fnIdx, 300)
        $block | Should -Match 'Continue\?'
    }

    It "Updates pip itself first" {
        $Script:AdvancedSource | Should -Match 'pip install --upgrade pip'
    }

    It "Updates setuptools and wheel" {
        $Script:AdvancedSource | Should -Match 'pip install --upgrade setuptools wheel'
    }
}

# ─────────────────────────────────────────────────────────────
# Clear-Cache
# ─────────────────────────────────────────────────────────────
Describe "Clear-Cache" {

    It "Purges pip cache" {
        $Script:AdvancedSource | Should -Match 'pip cache purge'
    }

    It "Cleans Windows temp files matching rns*" {
        $Script:AdvancedSource | Should -Match 'GetTempPath'
        $Script:AdvancedSource | Should -Match '-Filter "rns\*"'
    }

    It "Counts removed items" {
        $Script:AdvancedSource | Should -Match '\$removed\+\+'
    }

    It "Reports cleanup count to user" {
        $Script:AdvancedSource | Should -Match 'Cache cleaned.*removed'
    }
}

# ─────────────────────────────────────────────────────────────
# Export-Configuration
# ─────────────────────────────────────────────────────────────
Describe "Export-Configuration" {

    It "Uses timestamped export filename" {
        $Script:AdvancedSource | Should -Match 'yyyyMMdd_HHmmss.*\.zip'
    }

    It "Checks for .reticulum directory" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Export-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match '\.reticulum'
    }

    It "Checks for .nomadnetwork directory" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Export-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match '\.nomadnetwork'
    }

    It "Checks for .lxmf directory" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Export-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match '\.lxmf'
    }

    It "Reports when no config files exist" {
        $Script:AdvancedSource | Should -Match 'No configuration files found to export'
    }

    It "Uses Compress-Archive for zip creation" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Export-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Compress-Archive'
    }

    It "Cleans up temp directory after export" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Export-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Remove-Item.*tempExport.*Recurse.*Force'
    }

    It "Logs export operation" {
        $Script:AdvancedSource | Should -Match 'Exported configuration to'
    }
}

# ─────────────────────────────────────────────────────────────
# Import-Configuration (RNS004 path traversal)
# ─────────────────────────────────────────────────────────────
Describe "Import-Configuration: RNS004 Path Traversal Prevention" {

    It "Validates .zip extension" {
        $Script:AdvancedSource | Should -Match '-notmatch.*\.zip'
    }

    It "Checks file existence with Test-Path" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Import-Configuration')
        $block = $Script:AdvancedSource.Substring($fnIdx, 300)
        $block | Should -Match 'Test-Path \$importFile'
    }

    It "Uses ZipFile.OpenRead for archive validation" {
        $Script:AdvancedSource | Should -Match 'ZipFile.*OpenRead'
    }

    It "Checks for '..' path traversal in entries" {
        # Source has: $entry.FullName -match '\.\.'
        $Script:AdvancedSource | Should -Match 'entry\.FullName -match'
        $Script:AdvancedSource | Should -Match 'hasInvalidPaths'
    }

    It "Checks for absolute paths starting with /" {
        $Script:AdvancedSource | Should -Match "StartsWith\('/'\)"
    }

    It "Checks for absolute paths starting with \\" {
        $Script:AdvancedSource | Should -Match "StartsWith\('\\'\)"
    }

    It "Disposes zip handle after validation" {
        $Script:AdvancedSource | Should -Match '\$zip\.Dispose\(\)'
    }

    It "Logs security violations" {
        $Script:AdvancedSource | Should -Match 'SECURITY.*Rejected archive.*invalid paths'
    }

    It "Validates archive before extraction" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Import-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $validationIdx = $block.IndexOf('ZipFile')
        $expandIdx = $block.IndexOf('Expand-Archive')
        $validationIdx | Should -BeLessThan $expandIdx
    }

    It "Warns when archive lacks Reticulum config" {
        $Script:AdvancedSource | Should -Match 'does not appear to contain Reticulum configuration'
    }

    It "Requires confirmation before overwrite" {
        $Script:AdvancedSource | Should -Match 'overwrite your current configuration'
    }

    It "Creates backup before import" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Import-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $backupIdx = $block.IndexOf('New-Backup')
        $expandIdx = $block.IndexOf('Expand-Archive')
        $backupIdx | Should -BeGreaterThan 0
        $expandIdx | Should -BeGreaterThan $backupIdx
    }

    It "Cleans up temp import directory" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Import-Configuration')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Remove-Item.*tempImport.*Recurse.*Force'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-Log
# ─────────────────────────────────────────────────────────────
Describe "Show-Log" {

    It "Checks log file existence" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Show-Log')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Test-Path.*LogFile'
    }

    It "Shows last 50 entries" {
        $Script:AdvancedSource | Should -Match 'Get-Content.*LogFile.*Tail 50'
    }

    It "Reports when no log file found" {
        $Script:AdvancedSource | Should -Match 'No log file found'
    }
}

# ─────────────────────────────────────────────────────────────
# Test-ToolUpdate
# ─────────────────────────────────────────────────────────────
Describe "Test-ToolUpdate" {

    It "Queries GitHub releases API" {
        $Script:AdvancedSource | Should -Match 'api\.github\.com/repos/Nursedude/RNS-Management-Tool/releases/latest'
    }

    It "Compares current vs latest version" {
        $Script:AdvancedSource | Should -Match '\$latestVersion.*\$currentVersion'
    }

    It "Strips v prefix from version tag" {
        $Script:AdvancedSource | Should -Match "tag_name.*-replace.*\^v"
    }

    It "Shows download link when update available" {
        $Script:AdvancedSource | Should -Match 'github\.com/Nursedude/RNS-Management-Tool/releases/latest'
    }

    It "Reports when already on latest version" {
        $Script:AdvancedSource | Should -Match 'running the latest version'
    }

    It "Handles network errors gracefully" {
        $fnIdx = $Script:AdvancedSource.IndexOf('function Test-ToolUpdate')
        $fnEnd = $Script:AdvancedSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:AdvancedSource.Length }
        $block = $Script:AdvancedSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'catch'
        $block | Should -Match 'Unable to check for updates'
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

    It "Menu uses while loop (not recursive)" {
        $Script:AdvancedSource | Should -Match 'while\s*\(\$true\)'
    }

    It "Menu has back option (0)" {
        $Script:AdvancedSource | Should -Match '"0".*return'
    }

    It "Menu has all 8 options" {
        $Script:AdvancedSource | Should -Match '"1".*Update-PythonPackage'
        $Script:AdvancedSource | Should -Match '"2".*Install-Ecosystem'
        $Script:AdvancedSource | Should -Match '"3".*Clear-Cache'
        $Script:AdvancedSource | Should -Match '"4".*Export-Configuration'
        $Script:AdvancedSource | Should -Match '"5".*Import-Configuration'
        $Script:AdvancedSource | Should -Match '"6".*Reset-ToFactory'
        $Script:AdvancedSource | Should -Match '"7".*Show-Log'
        $Script:AdvancedSource | Should -Match '"8".*Test-ToolUpdate'
    }

    It "Menu handles invalid input gracefully" {
        $Script:AdvancedSource | Should -Match 'default'
        $Script:AdvancedSource | Should -Match 'Invalid option'
    }
}
