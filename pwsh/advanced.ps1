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

    Write-ColorOutput "Updating pip..." "Progress"
    Invoke-Pip install --upgrade pip

    Write-ColorOutput "Updating setuptools and wheel..." "Progress"
    Invoke-Pip install --upgrade setuptools wheel

    Write-ColorOutput "Python packages updated" "Success"
    pause
}

function Clear-Cache {
    Show-Section "Cleaning Cache"

    Write-ColorOutput "Clearing pip cache..." "Progress"
    Invoke-Pip cache purge 2>&1 | Out-File -FilePath $Script:LogFile -Append

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
    Show-LogMenu
}

function Show-LogMenu {
    while ($true) {
        Show-Header
        Write-Host "Log Viewer:" -ForegroundColor White
        Write-Host ""
        Write-Host "  --- System Journal ---" -ForegroundColor Cyan
        Write-Host "  1) View rnsd process logs"
        Write-Host "  2) View Windows Event Log (Application)"
        Write-Host ""
        Write-Host "  --- Application Logs ---" -ForegroundColor Cyan
        Write-Host "  3) View management tool log"
        Write-Host "  4) View MeshChat build log"
        Write-Host "  5) View NomadNet log"
        Write-Host "  6) View Sideband log"
        Write-Host ""
        Write-Host "  --- Search & List ---" -ForegroundColor Cyan
        Write-Host "  7) Search logs for keyword"
        Write-Host "  8) List all log files"
        Write-Host ""
        Write-Host "  0) Back"
        Write-Host ""

        $choice = Read-Host "Select option"

        switch ($choice) {
            "1" {
                Show-Section "rnsd Process Logs"
                $rnsdProc = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue
                if ($rnsdProc) {
                    Write-ColorOutput "rnsd is running (PID $($rnsdProc.Id))" "Success"
                } else {
                    Write-ColorOutput "rnsd is not currently running" "Warning"
                }
                # Check management log for rnsd entries
                if (Test-Path $Script:LogFile) {
                    Write-Host ""
                    Write-Host "Recent rnsd entries from management log:" -ForegroundColor Cyan
                    Write-Host ""
                    $entries = Select-String -Path $Script:LogFile -Pattern "rnsd|daemon|service" -ErrorAction SilentlyContinue | Select-Object -Last 20
                    if ($entries) {
                        $entries | ForEach-Object { Write-Host "  $($_.Line)" }
                    } else {
                        Write-ColorOutput "No rnsd entries found in management log" "Info"
                    }
                }
                pause
            }
            "2" {
                Show-Section "Windows Event Log (Application)"
                Write-ColorOutput "Showing recent Application event log entries..." "Info"
                Write-Host ""
                try {
                    Get-EventLog -LogName Application -Newest 30 -ErrorAction Stop |
                        Format-Table -Property TimeGenerated, EntryType, Source, Message -AutoSize -Wrap |
                        Out-String | Write-Host
                } catch {
                    Write-ColorOutput "Unable to read Windows Event Log: $_" "Warning"
                    Write-ColorOutput "Try running as Administrator for full access" "Info"
                }
                pause
            }
            "3" {
                Show-Section "Management Tool Log"
                if (Test-Path $Script:LogFile) {
                    Write-Host "File: $($Script:LogFile)" -ForegroundColor Cyan
                    Write-Host ""
                    Get-Content -Path $Script:LogFile -Tail 80
                } else {
                    Write-ColorOutput "No log file found" "Warning"
                }
                pause
            }
            "4" {
                Show-Section "MeshChat Build Log"
                $buildLog = Join-Path $env:USERPROFILE "meshchat_build.log"
                if (Test-Path $buildLog) {
                    Write-Host "File: $buildLog" -ForegroundColor Cyan
                    Write-Host "This log is from a failed build - it is removed on success." -ForegroundColor Yellow
                    Write-Host ""
                    Get-Content -Path $buildLog -Tail 80
                } else {
                    Write-ColorOutput "No MeshChat build log found" "Info"
                    Write-ColorOutput "This file only exists after a failed build (removed on success)" "Info"
                    # Check management log for MeshChat entries
                    if (Test-Path $Script:LogFile) {
                        Write-Host ""
                        Write-Host "MeshChat entries from management log:" -ForegroundColor Cyan
                        Write-Host ""
                        $entries = Select-String -Path $Script:LogFile -Pattern "meshchat|npm|node|build" -ErrorAction SilentlyContinue | Select-Object -Last 20
                        if ($entries) {
                            $entries | ForEach-Object { Write-Host "  $($_.Line)" }
                        } else {
                            Write-ColorOutput "No MeshChat entries found in management log" "Info"
                        }
                    }
                }
                pause
            }
            "5" {
                Show-Section "NomadNet Log"
                $nomadLog = Join-Path $env:USERPROFILE ".nomadnetwork\logfile"
                if (Test-Path $nomadLog) {
                    Write-Host "File: $nomadLog" -ForegroundColor Cyan
                    Write-Host ""
                    Get-Content -Path $nomadLog -Tail 80
                } else {
                    Write-ColorOutput "No NomadNet log found at $nomadLog" "Info"
                    Write-ColorOutput "NomadNet may not have been run yet" "Info"
                }
                pause
            }
            "6" {
                Show-Section "Sideband Log"
                $sbLog = Join-Path $env:USERPROFILE ".sideband\logfile"
                if (Test-Path $sbLog) {
                    Write-Host "File: $sbLog" -ForegroundColor Cyan
                    Write-Host ""
                    Get-Content -Path $sbLog -Tail 80
                } else {
                    Write-ColorOutput "No Sideband log found at $sbLog" "Info"
                    # Try alternate locations
                    $altLog = Get-ChildItem -Path (Join-Path $env:USERPROFILE ".config\sideband"), (Join-Path $env:USERPROFILE ".sideband") -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($altLog) {
                        Write-Host "Found log at: $($altLog.FullName)" -ForegroundColor Cyan
                        Write-Host ""
                        Get-Content -Path $altLog.FullName -Tail 80
                    } else {
                        Write-ColorOutput "Sideband may not have been run yet" "Info"
                    }
                }
                pause
            }
            "7" {
                Show-Section "Search Logs"
                $searchTerm = Read-Host "Enter search term"
                if ($searchTerm) {
                    Write-ColorOutput "Searching for '$searchTerm' in log files..." "Info"
                    Write-Host ""
                    $found = $false
                    $searchFiles = @($Script:LogFile, (Join-Path $env:USERPROFILE "meshchat_build.log"), (Join-Path $env:USERPROFILE ".nomadnetwork\logfile"), (Join-Path $env:USERPROFILE ".sideband\logfile"))
                    foreach ($f in $searchFiles) {
                        if (Test-Path $f) {
                            $matches = Select-String -Path $f -Pattern $searchTerm -SimpleMatch -ErrorAction SilentlyContinue
                            if ($matches) {
                                $found = $true
                                $matches | ForEach-Object {
                                    Write-Host "  $(Split-Path $_.Path -Leaf):$($_.LineNumber): $($_.Line)"
                                }
                            }
                        }
                    }
                    if (-not $found) {
                        Write-ColorOutput "No matches found" "Warning"
                    }
                }
                pause
            }
            "8" {
                Show-Section "All Log Files"
                Write-Host "Management logs:" -ForegroundColor White
                Write-Host ""
                $foundAny = $false
                foreach ($logPath in @($Script:LogFile, "$($Script:LogFile).1", "$($Script:LogFile).2", "$($Script:LogFile).3")) {
                    if (Test-Path $logPath) {
                        $foundAny = $true
                        $item = Get-Item $logPath
                        $lines = (Get-Content $logPath | Measure-Object -Line).Lines
                        Write-Host ("  {0} ({1:N0} bytes, {2} lines, modified: {3})" -f $item.Name, $item.Length, $lines, $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
                    }
                }
                if (-not $foundAny) {
                    Write-ColorOutput "No management logs found" "Warning"
                }

                Write-Host ""
                Write-Host "Application logs:" -ForegroundColor White
                Write-Host ""
                $appFound = $false
                foreach ($appLog in @((Join-Path $env:USERPROFILE "meshchat_build.log"), (Join-Path $env:USERPROFILE ".nomadnetwork\logfile"), (Join-Path $env:USERPROFILE ".sideband\logfile"))) {
                    if (Test-Path $appLog) {
                        $appFound = $true
                        $item = Get-Item $appLog
                        $lines = (Get-Content $appLog | Measure-Object -Line).Lines
                        Write-Host ("  {0} ({1:N0} bytes, {2} lines, modified: {3})" -f $item.Name, $item.Length, $lines, $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
                    }
                }
                if (-not $appFound) {
                    Write-ColorOutput "No application logs found" "Info"
                }

                Write-Host ""
                Write-ColorOutput "Logs directory: $env:USERPROFILE" "Info"
                pause
            }
            "0" { return }
            "" { return }
            default {
                Write-ColorOutput "Invalid option" "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
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
