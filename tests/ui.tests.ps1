#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/ui.ps1 — Color output, headers, progress, menus
.NOTES
    Covers: Write-ColorOutput (5 types), Show-Header, Show-Section,
    Show-Progress, Show-QuickStatus, Show-MainMenu
#>

BeforeAll {
    $Script:UiSource = Get-Content -Path "$PSScriptRoot/../pwsh/ui.ps1" -Raw

    $Script:UiAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:UiSource, [ref]$null, [ref]$null
    )
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "Write-ColorOutput function exists" {
        $Script:UiSource | Should -Match 'function Write-ColorOutput'
    }

    It "Show-Header function exists" {
        $Script:UiSource | Should -Match 'function Show-Header'
    }

    It "Show-Section function exists" {
        $Script:UiSource | Should -Match 'function Show-Section'
    }

    It "Show-Progress function exists" {
        $Script:UiSource | Should -Match 'function Show-Progress'
    }

    It "Show-QuickStatus function exists" {
        $Script:UiSource | Should -Match 'function Show-QuickStatus'
    }

    It "Show-MainMenu function exists" {
        $Script:UiSource | Should -Match 'function Show-MainMenu'
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

# ─────────────────────────────────────────────────────────────
# Write-ColorOutput
# ─────────────────────────────────────────────────────────────
Describe "Write-ColorOutput" {

    It "Accepts Message and Type parameters" {
        $Script:UiSource | Should -Match '\[string\]\$Message'
        $Script:UiSource | Should -Match '\[string\]\$Type'
    }

    It "Defaults Type to Info" {
        $Script:UiSource | Should -Match '\$Type\s*=\s*"Info"'
    }

    It "Logs all messages to log file" {
        $fnIdx = $Script:UiSource.IndexOf('function Write-ColorOutput')
        $block = $Script:UiSource.Substring($fnIdx, 300)
        $block | Should -Match 'Out-File.*LogFile.*Append'
    }

    Context "Color type mapping" {

        It "Success type uses green checkmark [checkmark]" {
            $Script:UiSource | Should -Match '"Success"'
            $Script:UiSource | Should -Match 'ForegroundColor Green'
        }

        It "Error type uses red cross [x]" {
            $Script:UiSource | Should -Match '"Error"'
            $Script:UiSource | Should -Match 'ForegroundColor Red'
        }

        It "Warning type uses yellow bang [!]" {
            $Script:UiSource | Should -Match '"Warning"'
            $Script:UiSource | Should -Match 'ForegroundColor Yellow'
        }

        It "Info type uses cyan info [i]" {
            $Script:UiSource | Should -Match '"Info"'
            $Script:UiSource | Should -Match 'ForegroundColor Cyan'
        }

        It "Progress type uses magenta arrow" {
            $Script:UiSource | Should -Match '"Progress"'
            $Script:UiSource | Should -Match 'ForegroundColor Magenta'
        }
    }

    It "Has default case for unknown types" {
        $Script:UiSource | Should -Match 'default\s*\{'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-Header
# ─────────────────────────────────────────────────────────────
Describe "Show-Header" {

    It "Clears the screen" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-Header')
        $block = $Script:UiSource.Substring($fnIdx, 100)
        $block | Should -Match 'Clear-Host'
    }

    It "Displays application title with version" {
        $Script:UiSource | Should -Match 'RNS MANAGEMENT TOOL.*Version'
    }

    It "Uses box-drawing characters for header" {
        $Script:UiSource | Should -Match '╔═'
        $Script:UiSource | Should -Match '╚═'
    }

    It "Shows platform info" {
        $Script:UiSource | Should -Match 'Platform'
    }

    It "Shows architecture" {
        $Script:UiSource | Should -Match 'Architecture'
    }

    It "Shows admin rights status" {
        $Script:UiSource | Should -Match 'Admin Rights'
        $Script:UiSource | Should -Match 'Script:IsAdmin'
    }

    It "Shows WSL availability when present" {
        $Script:UiSource | Should -Match 'Script:HasWSL'
    }

    It "Shows remote session indicator" {
        $Script:UiSource | Should -Match 'Script:IsRemoteSession'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-Section
# ─────────────────────────────────────────────────────────────
Describe "Show-Section" {

    It "Accepts Title parameter" {
        $Script:UiSource | Should -Match 'param\(\[string\]\$Title\)'
    }

    It "Uses blue color for section headers" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-Section')
        $fnEnd = $Script:UiSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:UiSource.Length }
        $block = $Script:UiSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'ForegroundColor Blue'
    }

    It "Prefixes with arrow character" {
        $Script:UiSource | Should -Match '▶.*Title'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-Progress
# ─────────────────────────────────────────────────────────────
Describe "Show-Progress" {

    It "Accepts Current, Total, and Activity parameters" {
        $Script:UiSource | Should -Match '\[int\]\$Current'
        $Script:UiSource | Should -Match '\[int\]\$Total'
        $Script:UiSource | Should -Match '\[string\]\$Activity'
    }

    It "Calculates percent complete" {
        $Script:UiSource | Should -Match 'Current / \$Total.*100'
    }

    It "Uses Write-Progress cmdlet" {
        $Script:UiSource | Should -Match 'Write-Progress.*Activity.*PercentComplete'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-QuickStatus
# ─────────────────────────────────────────────────────────────
Describe "Show-QuickStatus" {

    It "Uses box-drawing characters for status panel" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-QuickStatus')
        $fnEnd = $Script:UiSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:UiSource.Length }
        $block = $Script:UiSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match '┌─'
        $block | Should -Match '└─'
    }

    It "Checks rnsd process status" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-QuickStatus')
        $fnEnd = $Script:UiSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:UiSource.Length }
        $block = $Script:UiSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Process.*rnsd'
    }

    It "Shows green dot for running status" {
        $Script:UiSource | Should -Match '● rnsd: Running'
    }

    It "Shows yellow circle for stopped status" {
        $Script:UiSource | Should -Match '○ rnsd: Stopped'
    }

    It "Shows RNS version via pip" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-QuickStatus')
        $fnEnd = $Script:UiSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:UiSource.Length }
        $block = $Script:UiSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'pip show rns'
    }

    It "Shows 'Not installed' when RNS missing" {
        $Script:UiSource | Should -Match 'RNS: Not installed'
    }
}

# ─────────────────────────────────────────────────────────────
# Show-MainMenu
# ─────────────────────────────────────────────────────────────
Describe "Show-MainMenu" {

    It "Calls Show-Header" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-MainMenu')
        $block = $Script:UiSource.Substring($fnIdx, 200)
        $block | Should -Match 'Show-Header'
    }

    It "Calls Show-QuickStatus" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-MainMenu')
        $block = $Script:UiSource.Substring($fnIdx, 200)
        $block | Should -Match 'Show-QuickStatus'
    }

    It "Has Installation section" {
        $Script:UiSource | Should -Match 'Installation'
    }

    It "Has Management section" {
        $Script:UiSource | Should -Match 'Management'
    }

    It "Has Exit option (0)" {
        $Script:UiSource | Should -Match '0\) Exit'
    }

    It "Returns user choice" {
        $fnIdx = $Script:UiSource.IndexOf('function Show-MainMenu')
        $fnEnd = $Script:UiSource.Length
        $block = $Script:UiSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'return \$choice'
    }

    It "Includes MeshChat option (m)" {
        $Script:UiSource | Should -Match 'm\) Install MeshChat'
    }
}

# ─────────────────────────────────────────────────────────────
# RNS001: Command Safety (No Eval)
# ─────────────────────────────────────────────────────────────
Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:UiSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:UiSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }
}
