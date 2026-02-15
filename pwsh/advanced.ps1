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

function Export-Configuration {
    Show-Section "Export Configuration"

    $exportFile = Join-Path $env:USERPROFILE "reticulum_config_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"

    Write-ColorOutput "This will create a portable backup of your configuration" "Info"
    Write-Host ""

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    $hasConfig = $false
    if ((Test-Path $reticulumDir) -or (Test-Path $nomadDir) -or (Test-Path $lxmfDir)) {
        $hasConfig = $true
    }

    if (-not $hasConfig) {
        Write-ColorOutput "No configuration files found to export" "Warning"
        pause
        return
    }

    Write-ColorOutput "Creating export archive..." "Progress"

    # Create temporary directory
    $tempExport = Join-Path $env:TEMP "rns_export_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempExport -Force | Out-Null

    # Copy configs
    if (Test-Path $reticulumDir) {
        Copy-Item -Path $reticulumDir -Destination $tempExport -Recurse -Force
    }
    if (Test-Path $nomadDir) {
        Copy-Item -Path $nomadDir -Destination $tempExport -Recurse -Force
    }
    if (Test-Path $lxmfDir) {
        Copy-Item -Path $lxmfDir -Destination $tempExport -Recurse -Force
    }

    # Create zip archive
    Compress-Archive -Path "$tempExport\*" -DestinationPath $exportFile -Force

    # Cleanup
    Remove-Item -Path $tempExport -Recurse -Force

    Write-ColorOutput "Configuration exported to: $exportFile" "Success"
    "Exported configuration to: $exportFile" | Out-File -FilePath $Script:LogFile -Append

    pause
}

function Import-Configuration {
    Show-Section "Import Configuration"

    Write-Host "Enter the path to the export archive (.zip):" -ForegroundColor Cyan
    $importFile = Read-Host "Archive path"

    if (-not (Test-Path $importFile)) {
        Write-ColorOutput "File not found: $importFile" "Error"
        pause
        return
    }

    if ($importFile -notmatch '\.zip$') {
        Write-ColorOutput "Invalid file format. Expected .zip archive" "Error"
        pause
        return
    }

    # RNS004: Archive validation before extraction
    Write-ColorOutput "Validating archive structure..." "Info"

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($importFile)

        $hasInvalidPaths = $false
        $hasReticulumConfig = $false

        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '\.\.' -or $entry.FullName.StartsWith('/') -or $entry.FullName.StartsWith('\')) {
                $hasInvalidPaths = $true
                break
            }
            if ($entry.FullName -match '^\.reticulum|^\.nomadnetwork|^\.lxmf') {
                $hasReticulumConfig = $true
            }
        }

        $zip.Dispose()

        if ($hasInvalidPaths) {
            Write-ColorOutput "Security: Archive contains invalid paths (traversal attempt)" "Error"
            "SECURITY: Rejected archive with invalid paths: $importFile" | Out-File -FilePath $Script:LogFile -Append
            pause
            return
        }

        if (-not $hasReticulumConfig) {
            Write-ColorOutput "Archive does not appear to contain Reticulum configuration" "Warning"
            Write-Host "Expected directories: .reticulum/, .nomadnetwork/, .lxmf/"
            $continueAnyway = Read-Host "Continue anyway? (y/N)"
            if ($continueAnyway -ne 'y' -and $continueAnyway -ne 'Y') {
                Write-ColorOutput "Import cancelled" "Info"
                pause
                return
            }
        }

        Write-ColorOutput "Archive validation passed" "Success"
    }
    catch {
        Write-ColorOutput "Failed to validate archive: $_" "Error"
        pause
        return
    }

    Write-Host ""
    Write-ColorOutput "WARNING: This will overwrite your current configuration!" "Warning"
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-ColorOutput "Import cancelled" "Info"
        pause
        return
    }

    Write-ColorOutput "Creating backup of current configuration..." "Progress"
    New-Backup

    Write-ColorOutput "Importing configuration..." "Progress"

    try {
        $tempImport = Join-Path $env:TEMP "rns_import_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Expand-Archive -Path $importFile -DestinationPath $tempImport -Force

        Get-ChildItem -Path $tempImport -Directory | ForEach-Object {
            $dest = Join-Path $env:USERPROFILE $_.Name
            Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
        }

        Remove-Item -Path $tempImport -Recurse -Force

        Write-ColorOutput "Configuration imported successfully" "Success"
        "Imported configuration from: $importFile" | Out-File -FilePath $Script:LogFile -Append
    }
    catch {
        Write-ColorOutput "Failed to import configuration: $_" "Error"
    }

    pause
}

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
            "4" { Export-Configuration }
            "5" { Import-Configuration }
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
