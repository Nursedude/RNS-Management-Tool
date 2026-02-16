#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/install.ps1 — Installation functions
.NOTES
    Covers: Install-Python (3 methods), Install-Reticulum, Install-ReticulumWSL,
    Install-RNODE, Install-Sideband, Install-NomadNet, Install-MeshChat,
    Install-Ecosystem (reinstall).
    Uses .Contains() for literal string checks to avoid regex/source-text mismatch.
#>

BeforeAll {
    $Script:InstallSource = Get-Content -Path "$PSScriptRoot/../pwsh/install.ps1" -Raw

    $Script:InstallAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:InstallSource, [ref]$null, [ref]$null
    )
}

Describe "Function Existence" {

    It "All 8 install functions exist" {
        $Script:InstallSource.Contains('function Install-Python') | Should -BeTrue
        $Script:InstallSource.Contains('function Install-Reticulum') | Should -BeTrue
        $Script:InstallSource.Contains('function Install-ReticulumWSL') | Should -BeTrue
        $Script:InstallSource.Contains('function Install-RNODE') | Should -BeTrue
        $Script:InstallSource.Contains('function Install-Sideband') | Should -BeTrue
        $Script:InstallSource.Contains('function Install-NomadNet') | Should -BeTrue
        $Script:InstallSource.Contains('function Install-MeshChat') | Should -BeTrue
        $Script:InstallSource.Contains('function Install-Ecosystem') | Should -BeTrue
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

Describe "Install-Python" {

    It "Offers Microsoft Store, python.org, and winget options" {
        $Script:InstallSource.Contains('Microsoft Store') | Should -BeTrue
        $Script:InstallSource.Contains('python.org') | Should -BeTrue
        $Script:InstallSource.Contains('winget') | Should -BeTrue
    }

    It "Uses winget to install Python 3.11" {
        $Script:InstallSource.Contains('winget install Python.Python.3.11') | Should -BeTrue
    }

    It "Has cancel option" {
        $Script:InstallSource.Contains('Installation cancelled') | Should -BeTrue
    }
}

Describe "Install-Reticulum" {

    BeforeAll {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Reticulum')
        $fnEnd = $Script:InstallSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:InstallSource.Length }
        $Script:ReticulumBlock = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Has UseWSL parameter" {
        $Script:ReticulumBlock.Contains('$UseWSL') | Should -BeTrue
    }

    It "Delegates to Install-ReticulumWSL when UseWSL is true" {
        $Script:ReticulumBlock.Contains('Install-ReticulumWSL') | Should -BeTrue
    }

    It "Checks Python prerequisite" {
        $Script:ReticulumBlock.Contains('Test-Python') | Should -BeTrue
    }

    It "Installs RNS and LXMF via pip" {
        $Script:InstallSource.Contains('pip install rns --upgrade') | Should -BeTrue
        $Script:InstallSource.Contains('pip install lxmf --upgrade') | Should -BeTrue
    }

    It "Asks about NomadNet installation" {
        $Script:InstallSource.Contains('Install NomadNet') | Should -BeTrue
        $Script:InstallSource.Contains('pip install nomadnet --upgrade') | Should -BeTrue
    }

    It "Checks LASTEXITCODE after pip operations" {
        $Script:InstallSource.Contains('LASTEXITCODE') | Should -BeTrue
    }
}

Describe "Install-ReticulumWSL" {

    It "Calls Get-WSLDistribution to enumerate distros" {
        $Script:InstallSource.Contains('Get-WSLDistribution') | Should -BeTrue
    }

    It "Reports when no WSL distributions found" {
        $Script:InstallSource.Contains('No WSL distributions found') | Should -BeTrue
    }

    It "Suggests wsl --install when no distros" {
        $Script:InstallSource.Contains('wsl --install') | Should -BeTrue
    }

    It "Downloads Linux script to WSL" {
        $Script:InstallSource.Contains('curl') | Should -BeTrue
        $Script:InstallSource.Contains('rns_management_tool.sh') | Should -BeTrue
    }
}

Describe "Install-MeshChat" {

    BeforeAll {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-MeshChat')
        $fnEnd = $Script:InstallSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:InstallSource.Length }
        $Script:MeshChatBlock = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Checks for npm availability" {
        $Script:MeshChatBlock.Contains('Get-Command npm') | Should -BeTrue
    }

    It "Requires Node.js 18+" {
        $Script:InstallSource.Contains('Node.js 18+') | Should -BeTrue
    }

    It "Checks Node.js major version" {
        $Script:InstallSource.Contains('majorVersion') | Should -BeTrue
        $Script:InstallSource.Contains('-lt 18') | Should -BeTrue
    }

    It "Checks for git dependency" {
        $Script:MeshChatBlock.Contains('Get-Command git') | Should -BeTrue
    }

    It "Clones from correct repository" {
        $Script:InstallSource.Contains('liamcottle/reticulum-meshchat') | Should -BeTrue
    }

    It "Supports update of existing installation" {
        $Script:InstallSource.Contains('Update existing installation') | Should -BeTrue
        $Script:InstallSource.Contains('git pull origin main') | Should -BeTrue
    }

    It "Runs 4-step installation process" {
        $Script:InstallSource.Contains('Step 1/4') | Should -BeTrue
        $Script:InstallSource.Contains('Step 2/4') | Should -BeTrue
        $Script:InstallSource.Contains('Step 3/4') | Should -BeTrue
        $Script:InstallSource.Contains('Step 4/4') | Should -BeTrue
    }

    It "Runs npm audit fix" {
        $Script:InstallSource.Contains('npm audit fix') | Should -BeTrue
    }

    It "Verifies installation via package.json" {
        $Script:InstallSource.Contains('package.json') | Should -BeTrue
        $Script:InstallSource.Contains('ConvertFrom-Json') | Should -BeTrue
    }

    It "Uses Pop-Location for cleanup" {
        $Script:InstallSource.Contains('Pop-Location') | Should -BeTrue
    }
}

Describe "Install-RNODE" {

    BeforeAll {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-RNODE')
        $fnEnd = $Script:InstallSource.IndexOf("`nfunction ", $fnIdx + 10)
        if ($fnEnd -lt 0) { $fnEnd = $Script:InstallSource.Length }
        $Script:RnodeBlock = $Script:InstallSource.Substring($fnIdx, $fnEnd - $fnIdx)
    }

    It "Offers native Python and WSL installation options" {
        $Script:InstallSource.Contains('Install via Python') | Should -BeTrue
        $Script:InstallSource.Contains('Install via WSL') | Should -BeTrue
    }

    It "Offers Web Flasher" {
        $Script:InstallSource.Contains('Web Flasher') | Should -BeTrue
    }

    It "Installs rnodeconf via pip" {
        $Script:RnodeBlock.Contains('pip install rns --upgrade') | Should -BeTrue
    }

    It "Verifies rnodeconf after installation" {
        $Script:InstallSource.Contains('Get-Command rnodeconf') | Should -BeTrue
    }
}

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
        $block = $Script:InstallSource.Substring($fnIdx)
        $block.Contains('WARNING') | Should -BeTrue
        $block.Contains('reinstall all') | Should -BeTrue
    }

    It "Requires confirmation" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Ecosystem')
        $block = $Script:InstallSource.Substring($fnIdx)
        $block.Contains("-ne 'y'") | Should -BeTrue
    }

    It "Creates backup before reinstalling" {
        $fnIdx = $Script:InstallSource.IndexOf('function Install-Ecosystem')
        $block = $Script:InstallSource.Substring($fnIdx)
        $block.Contains('New-Backup') | Should -BeTrue
    }
}

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
