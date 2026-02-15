#########################################################
# pwsh/backup.ps1 — Backup, restore, export, import
# Dot-sourced by rns_management_tool.ps1
#########################################################

function New-Backup {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Creating Backup"

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    $backedUp = $false

    if ($PSCmdlet.ShouldProcess($Script:BackupDir, "Create backup")) {
        New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null

        if (Test-Path $reticulumDir) {
            Copy-Item -Path $reticulumDir -Destination $Script:BackupDir -Recurse -Force
            Write-ColorOutput "Backed up Reticulum config" "Success"
            $backedUp = $true
        }

        if (Test-Path $nomadDir) {
            Copy-Item -Path $nomadDir -Destination $Script:BackupDir -Recurse -Force
            Write-ColorOutput "Backed up NomadNet config" "Success"
            $backedUp = $true
        }

        if (Test-Path $lxmfDir) {
            Copy-Item -Path $lxmfDir -Destination $Script:BackupDir -Recurse -Force
            Write-ColorOutput "Backed up LXMF config" "Success"
            $backedUp = $true
        }

        if ($backedUp) {
            Write-ColorOutput "Backup saved to: $Script:BackupDir" "Success"
        } else {
            Write-ColorOutput "No configuration files found to backup" "Warning"
        }
    }

    pause
}

function Restore-Backup {
    Show-Section "Restore Backup"

    $backups = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter ".reticulum_backup_*" | Sort-Object LastWriteTime -Descending

    if ($backups.Count -eq 0) {
        Write-ColorOutput "No backups found" "Warning"
        pause
        return
    }

    Write-Host "Available backups:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-Host "  $($i + 1)) $($backups[$i].Name) - $($backups[$i].LastWriteTime)"
    }
    Write-Host ""

    $selection = Read-Host "Select backup to restore (0 to cancel)"

    if ($selection -eq "0") {
        return
    }

    $selectedBackup = $backups[[int]$selection - 1]

    Write-Host ""
    Write-ColorOutput "WARNING: This will overwrite your current configuration!" "Warning"
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Write-ColorOutput "Restoring from: $($selectedBackup.FullName)" "Progress"

        $items = Get-ChildItem -Path $selectedBackup.FullName -Directory
        foreach ($item in $items) {
            $dest = Join-Path $env:USERPROFILE $item.Name
            Copy-Item -Path $item.FullName -Destination $dest -Recurse -Force
        }

        Write-ColorOutput "Backup restored successfully" "Success"
    }

    pause
}

function Get-AllBackups {
    Show-Section "All Backups"

    $backups = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter ".reticulum_backup_*" -ErrorAction SilentlyContinue | Sort-Object Name

    if (-not $backups -or $backups.Count -eq 0) {
        Write-ColorOutput "No backups found" "Warning"
        pause
        return
    }

    Write-Host "Found $($backups.Count) backup(s):" -ForegroundColor White
    Write-Host ""

    foreach ($backup in $backups) {
        # Extract date from backup name (format: .reticulum_backup_YYYYMMDD_HHMMSS)
        $datePart = $backup.Name -replace '\.reticulum_backup_', ''
        if ($datePart -match '(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})') {
            $formattedDate = "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])"
        } else {
            $formattedDate = $backup.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }

        $backupSize = "{0:N1} MB" -f ((Get-ChildItem $backup.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)

        Write-Host "  " -NoNewline
        Write-Host ([char]0x25CF) -ForegroundColor Green -NoNewline
        Write-Host " $formattedDate (Size: $backupSize)"
    }

    pause
}

function Remove-OldBackups {
    Show-Section "Delete Old Backups"

    $backups = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter ".reticulum_backup_*" -ErrorAction SilentlyContinue | Sort-Object Name

    if (-not $backups -or $backups.Count -eq 0) {
        Write-ColorOutput "No backups found to delete" "Warning"
        pause
        return
    }

    if ($backups.Count -le 3) {
        Write-ColorOutput "Only $($backups.Count) backup(s) exist. Keeping all." "Info"
        pause
        return
    }

    $toDelete = $backups.Count - 3
    Write-Host "This will keep the 3 most recent backups and delete older ones." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Backups to delete: $toDelete"
    Write-Host ""

    $confirm = Read-Host "Delete $toDelete old backup(s)? (y/N)"
    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        $deleted = 0
        for ($i = 0; $i -lt $toDelete; $i++) {
            Remove-Item -Path $backups[$i].FullName -Recurse -Force -ErrorAction SilentlyContinue
            $deleted++
        }
        Write-ColorOutput "Deleted $deleted old backup(s)" "Success"
        Write-RnsLog "Deleted $deleted old backups" "INFO"
    } else {
        Write-ColorOutput "Cancelled" "Info"
    }

    pause
}

function Export-RnsConfiguration {
    Show-Section "Export Configuration"

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $exportFile = Join-Path $env:USERPROFILE "reticulum_config_export_$timestamp.zip"

    Write-Host "This will create a portable backup of your configuration." -ForegroundColor Yellow
    Write-Host ""

    $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
    $nomadDir = Join-Path $env:USERPROFILE ".nomadnetwork"
    $lxmfDir = Join-Path $env:USERPROFILE ".lxmf"

    $hasConfig = (Test-Path $reticulumDir) -or (Test-Path $nomadDir) -or (Test-Path $lxmfDir)

    if (-not $hasConfig) {
        Write-ColorOutput "No configuration files found to export" "Warning"
        pause
        return
    }

    Write-ColorOutput "Creating export archive..." "Progress"

    $tempExport = Join-Path $env:TEMP "rns_export_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempExport -Force | Out-Null

    if (Test-Path $reticulumDir) {
        Copy-Item -Path $reticulumDir -Destination $tempExport -Recurse -Force
    }
    if (Test-Path $nomadDir) {
        Copy-Item -Path $nomadDir -Destination $tempExport -Recurse -Force
    }
    if (Test-Path $lxmfDir) {
        Copy-Item -Path $lxmfDir -Destination $tempExport -Recurse -Force
    }

    Compress-Archive -Path "$tempExport\*" -DestinationPath $exportFile -Force
    Remove-Item -Path $tempExport -Recurse -Force

    Write-ColorOutput "Configuration exported to: $exportFile" "Success"
    Write-RnsLog "Exported configuration to: $exportFile" "INFO"

    pause
}

function Import-RnsConfiguration {
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

        # Check for path traversal attempts
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
            Write-RnsLog "SECURITY: Rejected archive with invalid paths: $importFile" "ERROR"
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
        Write-RnsLog "Imported configuration from: $importFile" "INFO"
    }
    catch {
        Write-ColorOutput "Failed to import configuration: $_" "Error"
    }

    pause
}

function Show-BackupMenu {
    while ($true) {
        Show-Section "Backup/Restore Configuration"

        # Show backup status
        $backups = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter ".reticulum_backup_*" -ErrorAction SilentlyContinue
        $backupCount = if ($backups) { $backups.Count } else { 0 }

        Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor White
        Write-Host "│  " -ForegroundColor White -NoNewline
        Write-Host "Backup Status" -ForegroundColor Cyan -NoNewline
        Write-Host "                                          │" -ForegroundColor White
        Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor White
        Write-Host "│  Available backups: " -ForegroundColor White -NoNewline
        Write-Host "$backupCount" -ForegroundColor Green -NoNewline
        Write-Host "                                    │" -ForegroundColor White

        $reticulumDir = Join-Path $env:USERPROFILE ".reticulum"
        if (Test-Path $reticulumDir) {
            $configSize = "{0:N1} MB" -f ((Get-ChildItem $reticulumDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
            Write-Host "│  Config size: " -ForegroundColor White -NoNewline
            Write-Host "$configSize" -ForegroundColor Green -NoNewline
            $pad = " " * (40 - $configSize.Length)
            Write-Host "$pad│" -ForegroundColor White
        }

        Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor White
        Write-Host ""

        Write-Host "Backup & Restore:" -ForegroundColor White
        Write-Host ""
        Write-Host "  1) Create backup"
        Write-Host "  2) Restore from backup"
        Write-Host "  3) List all backups"
        Write-Host "  4) Delete old backups"
        Write-Host "  5) Export configuration (portable)"
        Write-Host "  6) Import configuration"
        Write-Host ""
        Write-Host "  0) Back to Main Menu"
        Write-Host ""

        $choice = Read-Host "Select option"

        switch ($choice) {
            "1" { New-Backup }
            "2" { Restore-Backup }
            "3" { Get-AllBackups }
            "4" { Remove-OldBackups }
            "5" { Export-RnsConfiguration }
            "6" { Import-RnsConfiguration }
            "0" { return }
            "" { return }
            default { Write-ColorOutput "Invalid option" "Error"; Start-Sleep -Seconds 1 }
        }
    }
}
