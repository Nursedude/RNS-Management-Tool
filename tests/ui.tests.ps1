#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/ui.ps1 — Color output, headers, progress, menus
.NOTES
    Covers: Write-ColorOutput (5 types), Show-Header, Show-Section,
    Show-Progress, Show-QuickStatus, Show-MainMenu.
    Uses .Contains() for literal string checks to avoid regex/source-text mismatch.
#>

BeforeAll {
    $Script:UiSource = Get-Content -Path "$PSScriptRoot/../pwsh/ui.ps1" -Raw

    $Script:UiAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:UiSource, [ref]$null, [ref]$null
    )
}

Describe "Function Existence" {

    It "All 6 UI functions exist" {
        $Script:UiSource.Contains('function Write-ColorOutput') | Should -BeTrue
        $Script:UiSource.Contains('function Show-Header') | Should -BeTrue
        $Script:UiSource.Contains('function Show-Section') | Should -BeTrue
        $Script:UiSource.Contains('function Show-Progress') | Should -BeTrue
        $Script:UiSource.Contains('function Show-QuickStatus') | Should -BeTrue
        $Script:UiSource.Contains('function Show-MainMenu') | Should -BeTrue
    }

    It "ui.ps1 has exactly 6 functions" {
        $functionCount = ([regex]::Matches(
            $Script:UiSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 6
    }
}

Describe "Write-ColorOutput" {

    It "Accepts Message and Type parameters" {
        $Script:UiSource.Contains('[string]$Message') | Should -BeTrue
        $Script:UiSource.Contains('[string]$Type') | Should -BeTrue
    }

    It "Defaults Type to Info" {
        $Script:UiSource.Contains('$Type = "Info"') | Should -BeTrue
    }

    It "Logs all messages to log file" {
        $fnIdx = $Script:UiSource.IndexOf('function Write-ColorOutput')
        $block = $Script:UiSource.Substring($fnIdx, 300)
        $block.Contains('Out-File') | Should -BeTrue
        $block.Contains('LogFile') | Should -BeTrue
        $block.Contains('Append') | Should -BeTrue
    }

    It "Maps all 5 color types" {
        $Script:UiSource.Contains('"Success"') | Should -BeTrue
        $Script:UiSource.Contains('"Error"') | Should -BeTrue
        $Script:UiSource.Contains('"Warning"') | Should -BeTrue
        $Script:UiSource.Contains('"Info"') | Should -BeTrue
        $Script:UiSource.Contains('"Progress"') | Should -BeTrue
    }

    It "Uses correct foreground colors" {
        $Script:UiSource.Contains('ForegroundColor Green') | Should -BeTrue
        $Script:UiSource.Contains('ForegroundColor Red') | Should -BeTrue
        $Script:UiSource.Contains('ForegroundColor Yellow') | Should -BeTrue
        $Script:UiSource.Contains('ForegroundColor Cyan') | Should -BeTrue
        $Script:UiSource.Contains('ForegroundColor Magenta') | Should -BeTrue
    }

    It "Has default case for unknown types" {
        $Script:UiSource.Contains('default {') | Should -BeTrue
    }
}

Describe "Show-Header" {

    It "Clears the screen" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-Header')
        $block = $Script:UiSource.Substring($fnIdx, 100)
        $block.Contains('Clear-Host') | Should -BeTrue
    }

    It "Displays application title" {
        $Script:UiSource.Contains('RNS MANAGEMENT TOOL') | Should -BeTrue
    }

    It "Uses box-drawing characters for header" {
        $Script:UiSource.Contains('╔═') | Should -BeTrue
        $Script:UiSource.Contains('╚═') | Should -BeTrue
    }

    It "Shows environment info" {
        $Script:UiSource.Contains('Platform') | Should -BeTrue
        $Script:UiSource.Contains('Architecture') | Should -BeTrue
        $Script:UiSource.Contains('Admin Rights') | Should -BeTrue
    }
}

Describe "Show-Section" {

    It "Accepts Title parameter" {
        $Script:UiSource.Contains('[string]$Title') | Should -BeTrue
    }

    It "Uses blue color for section headers" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-Section')
        $fnEnd = $Script:UiSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:UiSource.Length }
        $block = $Script:UiSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block.Contains('ForegroundColor Blue') | Should -BeTrue
    }
}

Describe "Show-Progress" {

    It "Accepts Current, Total, and Activity parameters" {
        $Script:UiSource.Contains('[int]$Current') | Should -BeTrue
        $Script:UiSource.Contains('[int]$Total') | Should -BeTrue
        $Script:UiSource.Contains('[string]$Activity') | Should -BeTrue
    }

    It "Uses Write-Progress cmdlet" {
        $Script:UiSource.Contains('Write-Progress') | Should -BeTrue
        $Script:UiSource.Contains('PercentComplete') | Should -BeTrue
    }
}

Describe "Show-QuickStatus" {

    BeforeAll {
        $fnIdx = $Script:UiSource.IndexOf('function Show-QuickStatus')
        $fnEnd = $Script:UiSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:UiSource.Length }
        $Script:StatusBlock = $Script:UiSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Uses box-drawing characters for status panel" {
        $Script:StatusBlock.Contains('┌─') | Should -BeTrue
        $Script:StatusBlock.Contains('└─') | Should -BeTrue
    }

    It "Checks rnsd process status" {
        $Script:StatusBlock.Contains('Get-Process') | Should -BeTrue
        $Script:StatusBlock.Contains('rnsd') | Should -BeTrue
    }

    It "Shows running and stopped status indicators" {
        $Script:UiSource.Contains('rnsd: Running') | Should -BeTrue
        $Script:UiSource.Contains('rnsd: Stopped') | Should -BeTrue
    }

    It "Shows RNS version via pip" {
        $Script:StatusBlock.Contains('pip show rns') | Should -BeTrue
    }

    It "Shows Not installed when RNS missing" {
        $Script:UiSource.Contains('RNS: Not installed') | Should -BeTrue
    }
}

Describe "Show-MainMenu" {

    BeforeAll {
        $fnIdx = $Script:UiSource.IndexOf('function Show-MainMenu')
        $Script:MenuBlock = $Script:UiSource.Substring($fnIdx)
    }

    It "Calls Show-Header and Show-QuickStatus" {
        $Script:MenuBlock.Contains('Show-Header') | Should -BeTrue
        $Script:MenuBlock.Contains('Show-QuickStatus') | Should -BeTrue
    }

    It "Has Installation and Management sections" {
        $Script:UiSource.Contains('Installation') | Should -BeTrue
        $Script:UiSource.Contains('Management') | Should -BeTrue
    }

    It "Has Exit option and MeshChat option" {
        $Script:UiSource.Contains('0) Exit') | Should -BeTrue
        $Script:UiSource.Contains('m) Install MeshChat') | Should -BeTrue
    }

    It "Returns user choice" {
        $Script:MenuBlock.Contains('return $choice') | Should -BeTrue
    }
}

Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:UiSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:UiSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }
}
