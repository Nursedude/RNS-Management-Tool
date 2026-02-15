#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/install.ps1 — Installation functions
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: Install-Python (3 methods), Install-Reticulum, Install-ReticulumWSL,
    Install-RNODE, Install-Sideband, Install-NomadNet, Install-MeshChat,
    Install-Ecosystem (reinstall)
#>

BeforeAll {
    $Script:InstallSource = Get-Content -Path "$PSScriptRoot/../pwsh/install.ps1" -Raw

    $Script:InstallAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:InstallSource, [ref]$null, [ref]$null
    )
}

# ─────────────────────────────────────────────────────────────
# Function Existence
# ─────────────────────────────────────────────────────────────
Describe "Function Existence" {

    It "Install-Python function exists" {
        $Script:InstallSource | Should -Match 'function Install-Python'
    }

    It "Install-Reticulum function exists" {
        $Script:InstallSource | Should -Match 'function Install-Reticulum'
    }

    It "Install-ReticulumWSL function exists" {
        $Script:InstallSource | Should -Match 'function Install-ReticulumWSL'
    }

    It "Install-RNODE function exists" {
        $Script:InstallSource | Should -Match 'function Install-RNODE'
    }

    It "Install-Sideband function exists" {
        $Script:InstallSource | Should -Match 'function Install-Sideband'
    }

    It "Install-NomadNet function exists" {
        $Script:InstallSource | Should -Match 'function Install-NomadNet'
    }

    It "Install-MeshChat function exists" {
        $Script:InstallSource | Should -Match 'function Install-MeshChat'
    }

    It "Install-Ecosystem function exists" {
        $Script:InstallSource | Should -Match 'function Install-Ecosystem'
    }

    It "install.ps1 has exactly 8 functions" {
        $functionCount = ([regex]::Matches(
            $Script:InstallSource,
            '^\s*function\s+',
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )).Count
        $functionCount | Should -Be 8
    }
}

# ─────────────────────────────────────────────────────────────
# Install-Python (3 methods)
# ─────────────────────────────────────────────────────────────
Describe "Install-Python" {

    It "Offers Microsoft Store option" {
        $Script:InstallSource | Should -Match 'Microsoft Store'
    }

    It "Offers python.org option" {
        $Script:InstallSource | Should -Match 'python\.org'
    }

    It "Offers winget option" {
        $Script:InstallSource | Should -Match 'winget'
    }

    It "Uses winget to install Python 3.11" {
        $Script:InstallSource | Should -Match 'winget install Python\.Python\.3\.11'
    }

    It "Has cancel option" {
        $Script:InstallSource | Should -Match 'Installation cancelled'
    }
}

# ─────────────────────────────────────────────────────────────
# Install-Reticulum
# ─────────────────────────────────────────────────────────────
Describe "Install-Reticulum" {

    It "Has UseWSL parameter" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Reticulum')
        $block = $Script:InstallSource.Substring($fnIdx, 200)
        $block | Should -Match '\$UseWSL'
    }

    It "Delegates to Install-ReticulumWSL when UseWSL is true" {
        $Script:InstallSource | Should -Match 'Install-ReticulumWSL'
    }

    It "Checks Python prerequisite" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Reticulum')
        $fnEnd = $Script:InstallSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:InstallSource.Length }
        $block = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Test-Python'
    }

    It "Installs RNS via pip" {
        $Script:InstallSource | Should -Match 'pip install rns --upgrade'
    }

    It "Installs LXMF via pip" {
        $Script:InstallSource | Should -Match 'pip install lxmf --upgrade'
    }

    It "Asks about NomadNet installation" {
        $Script:InstallSource | Should -Match 'Install NomadNet.*terminal client'
    }

    It "Installs NomadNet when confirmed" {
        $Script:InstallSource | Should -Match 'pip install nomadnet --upgrade'
    }

    It "Logs pip output to log file" {
        $Script:InstallSource | Should -Match 'Out-File.*LogFile.*Append'
    }

    It "Checks LASTEXITCODE after pip operations" {
        $Script:InstallSource | Should -Match 'LASTEXITCODE'
    }
}

# ─────────────────────────────────────────────────────────────
# Install-ReticulumWSL
# ─────────────────────────────────────────────────────────────
Describe "Install-ReticulumWSL" {

    It "Calls Get-WSLDistribution to enumerate distros" {
        $Script:InstallSource | Should -Match 'Get-WSLDistribution'
    }

    It "Reports when no WSL distributions found" {
        $Script:InstallSource | Should -Match 'No WSL distributions found'
    }

    It "Suggests wsl --install when no distros" {
        $Script:InstallSource | Should -Match 'wsl --install'
    }

    It "Lets user select a distribution" {
        $Script:InstallSource | Should -Match 'Select distribution'
    }

    It "Downloads Linux script to WSL" {
        $Script:InstallSource | Should -Match 'curl.*rns_management_tool\.sh'
    }
}

# ─────────────────────────────────────────────────────────────
# Install-MeshChat
# ─────────────────────────────────────────────────────────────
Describe "Install-MeshChat" {

    It "Checks for npm availability" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-MeshChat')
        $block = $Script:InstallSource.Substring($fnIdx, 300)
        $block | Should -Match 'Get-Command npm'
    }

    It "Requires Node.js 18+" {
        $Script:InstallSource | Should -Match 'Node\.js 18\+'
    }

    It "Checks Node.js major version" {
        $Script:InstallSource | Should -Match 'majorVersion.*-lt 18'
    }

    It "Checks for git dependency" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-MeshChat')
        $fnEnd = $Script:InstallSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:InstallSource.Length }
        $block = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'Get-Command git'
    }

    It "Clones from correct repository" {
        $Script:InstallSource | Should -Match 'git clone.*liamcottle/reticulum-meshchat'
    }

    It "Supports update of existing installation" {
        $Script:InstallSource | Should -Match 'Update existing installation'
    }

    It "Uses git pull for updates" {
        $Script:InstallSource | Should -Match 'git pull origin main'
    }

    It "Runs 4-step installation process" {
        $Script:InstallSource | Should -Match 'Step 1/4.*repository'
        $Script:InstallSource | Should -Match 'Step 2/4.*npm dependencies'
        $Script:InstallSource | Should -Match 'Step 3/4.*security audit'
        $Script:InstallSource | Should -Match 'Step 4/4.*Building'
    }

    It "Runs npm audit fix" {
        $Script:InstallSource | Should -Match 'npm audit fix'
    }

    It "Verifies installation via package.json" {
        $Script:InstallSource | Should -Match 'package\.json'
        $Script:InstallSource | Should -Match 'ConvertFrom-Json'
    }

    It "Logs MeshChat version after install" {
        $Script:InstallSource | Should -Match 'Write-RnsLog.*MeshChat installed'
    }

    It "Uses Pop-Location for cleanup" {
        $Script:InstallSource | Should -Match 'Pop-Location'
    }
}

# ─────────────────────────────────────────────────────────────
# Install-RNODE
# ─────────────────────────────────────────────────────────────
Describe "Install-RNODE" {

    It "Offers native Python installation" {
        $Script:InstallSource | Should -Match 'Install via Python.*Native Windows'
    }

    It "Offers WSL installation" {
        $Script:InstallSource | Should -Match 'Install via WSL'
    }

    It "Offers Web Flasher" {
        $Script:InstallSource | Should -Match 'Web Flasher'
    }

    It "Installs rnodeconf via pip" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-RNODE')
        $fnEnd = $Script:InstallSource.IndexOf('function', $fnIdx + 20)
        if ($fnEnd -lt 0) { $fnEnd = $Script:InstallSource.Length }
        $block = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'pip install rns --upgrade'
    }

    It "Verifies rnodeconf after installation" {
        $Script:InstallSource | Should -Match 'Get-Command rnodeconf'
    }
}

# ─────────────────────────────────────────────────────────────
# Install-Ecosystem
# ─────────────────────────────────────────────────────────────
Describe "Install-Ecosystem" {

    It "Uses SupportsShouldProcess" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Ecosystem')
        $fnIdx | Should -BeGreaterOrEqual 0
        $cbIdx = $Script:InstallSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
        $cbIdx | Should -BeGreaterThan $fnIdx
        ($cbIdx - $fnIdx) | Should -BeLessThan 100
    }

    It "Warns before reinstalling" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Ecosystem')
        $fnEnd = $Script:InstallSource.Length
        $block = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'WARNING.*reinstall all'
    }

    It "Requires confirmation" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Ecosystem')
        $fnEnd = $Script:InstallSource.Length
        $block = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match "confirm.*-ne 'y'"
    }

    It "Creates backup before reinstalling" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Ecosystem')
        $fnEnd = $Script:InstallSource.Length
        $block = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
        $block | Should -Match 'New-Backup'
    }
}

# ─────────────────────────────────────────────────────────────
# RNS001: Command Safety (No Eval)
# ─────────────────────────────────────────────────────────────
Describe "RNS001: Command Safety (No Eval)" {

    It "Source does not use Invoke-Expression" {
        $Script:InstallSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:InstallSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }

    It "AST contains no Invoke-Expression commands" {
        $iexCmds = $Script:InstallAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-Expression'
        }, $true)
        $iexCmds.Count | Should -Be 0
    }
}
