#########################################################
# pwsh/advanced.ps1 — Advanced options, config management
# Dot-sourced by rns_management_tool.ps1
#########################################################

function Update-PythonPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Updating Python Packages"

    Write-ColorOutput "This will update pip and all Python packages" "Info"
    $confirm = Read-Host "Continue? (Y/n)"

    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        return
    }

    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    Write-ColorOutput "Updating pip..." "Progress"
    & $pip install --upgrade pip

    Write-ColorOutput "Updating setuptools and wheel..." "Progress"
    & $pip install --upgrade setuptools wheel

    Write-ColorOutput "Python packages updated" "Success"
    pause
}

function Clear-Cache {
    Show-Section "Cleaning Cache"

    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    Write-ColorOutput "Clearing pip cache..." "Progress"
    & $pip cache purge 2>&1 | Out-File -FilePath $Script:LogFile -Append

    Write-ColorOutput "Clearing Windows temp files..." "Progress"
    $tempPath = [System.IO.Path]::GetTempPath()
    $removed = 0
    Get-ChildItem -Path $tempPath -Filter "rns*" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        $removed++
    }

    Write-ColorOutput "Cache cleaned ($removed items removed)" "Success"
    pause
}

# Export/Import consolidated in pwsh/backup.ps1 (Export-RnsConfiguration, Import-RnsConfiguration)
# Removed duplicate Export-Configuration and Import-Configuration functions (SECURITY_REVIEW R8)

function Reset-ToFactory {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Reset to Factory Defaults"

    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                      WARNING!                          ║" -ForegroundColor Red
    Write-Host "║   This will DELETE all Reticulum configuration!        ║" -ForegroundColor Red
    Write-Host "║   Your identities and messages will be LOST forever!   ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "This will remove:" -ForegroundColor Yellow
    Write-Host "  • .reticulum/     (identities, keys, config)"
    Write-Host "  • .nomadnetwork/  (NomadNet data)"
    Write-Host "  • .lxmf/          (messages)"
    Write-Host ""

    $confirm = Read-Host "Type 'RESET' to confirm factory reset"

    if ($confirm -ne "RESET") {
        Write-ColorOutput "Reset cancelled - confirmation not received" "Info"
        pause
        return
    }

    Write-ColorOutput "Creating final backup before reset..." "Progress"
    New-Backup

    Write-ColorOutput "Removing configuration directories..." "Progress"

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    if (Test-Path $reticulumDir) {
        Remove-Item -Path $reticulumDir -Recurse -Force
        Write-ColorOutput "Removed .reticulum" "Success"
    }

    if (Test-Path $nomadDir) {
        Remove-Item -Path $nomadDir -Recurse -Force
        Write-ColorOutput "Removed .nomadnetwork" "Success"
    }

    if (Test-Path $lxmfDir) {
        Remove-Item -Path $lxmfDir -Recurse -Force
        Write-ColorOutput "Removed .lxmf" "Success"
    }

    Write-ColorOutput "Factory reset complete" "Success"
    Write-ColorOutput "Run 'rnsd --daemon' to create fresh configuration" "Info"
    "Factory reset performed - all configurations removed" | Out-File -FilePath $Script:LogFile -Append

    pause
}

function Show-Log {
    Show-Section "Recent Log Entries"

    if (Test-Path $Script:LogFile) {
        Write-Host "Last 50 log entries:" -ForegroundColor Cyan
        Write-Host ""
        Get-Content -Path $Script:LogFile -Tail 50
    }
    else {
        Write-ColorOutput "No log file found" "Warning"
    }

    pause
}

function Test-ToolUpdate {
    Show-Section "Checking for Updates"

    Write-ColorOutput "Checking GitHub for latest version..." "Progress"

    try {
        $latestUrl = "https://api.github.com/repos/Nursedude/RNS-Management-Tool/releases/latest"
        $response = Invoke-RestMethod -Uri $latestUrl -ErrorAction Stop

        $latestVersion = $response.tag_name -replace '^v', ''
        $currentVersion = $Script:Version

        Write-Host ""
        Write-Host "Current Version: $currentVersion" -ForegroundColor Cyan
        Write-Host "Latest Version:  $latestVersion" -ForegroundColor Cyan
        Write-Host ""

        if ($latestVersion -gt $currentVersion) {
            Write-ColorOutput "A new version is available!" "Success"
            Write-Host ""
            Write-Host "Download from: https://github.com/Nursedude/RNS-Management-Tool/releases/latest" -ForegroundColor Yellow
        }
        else {
            Write-ColorOutput "You are running the latest version" "Success"
        }
    }
    catch {
        Write-ColorOutput "Unable to check for updates: $_" "Error"
    }

    pause
}

function Show-AdvancedMenu {
    while ($true) {
        Show-Header
        Write-Host "Advanced Options:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1) Update Python Packages"
        Write-Host "  2) Reinstall All Components"
        Write-Host "  3) Clean Cache and Temporary Files"
        Write-Host "  4) Export Configuration"
        Write-Host "  5) Import Configuration"
        Write-Host "  6) Reset to Factory Defaults"
        Write-Host "  7) View Logs"
        Write-Host "  8) Check for Tool Updates"
        Write-Host "  0) Back to Main Menu"
        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1" { Update-PythonPackage }
            "2" { Install-Ecosystem }
            "3" { Clear-Cache }
            "4" { Export-RnsConfiguration }
            "5" { Import-RnsConfiguration }
            "6" { Reset-ToFactory }
            "7" { Show-Log }
            "8" { Test-ToolUpdate }
            "0" { return }
            default {
                Write-ColorOutput "Invalid option" "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
