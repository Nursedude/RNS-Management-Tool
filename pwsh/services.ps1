#########################################################
# pwsh/services.ps1 — Service management, autostart
# Dot-sourced by rns_management_tool.ps1
#########################################################

# Scheduled-task names for the Windows keep-alive (logon trigger + restart-on-failure).
# No admin required — tasks run in the user's interactive session at RunLevel Limited.
$Script:RnsdTaskName      = "RNS_rnsd_autostart"
$Script:MeshChatXTaskName = "RNS_meshchatx_autostart"

function Show-Status {
    Show-Section "Reticulum Status"

    # Check if rnsd is running
    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue

    if ($rnsdProcess) {
        Write-ColorOutput "rnsd daemon: Running (PID: $($rnsdProcess.Id))" "Success"
    } else {
        Write-ColorOutput "rnsd daemon: Not running" "Warning"
    }

    Write-Host ""
    Write-Host "Installed Components:" -ForegroundColor Cyan

    # Check Python packages
    $pipCmd = Get-PipCommand
    $packages = @("rns", "lxmf", "nomadnet")
    foreach ($package in $packages) {
        try {
            if ($pipCmd) {
                $version = & $pipCmd show $package 2>$null | Select-String "Version:" | ForEach-Object { $_ -replace "Version:\s*", "" }
            } else {
                $version = Invoke-Pip show $package 2>$null | Select-String "Version:" | ForEach-Object { $_ -replace "Version:\s*", "" }
            }
            if ($version) {
                Write-ColorOutput "$package : v$version" "Success"
            } else {
                Write-ColorOutput "$package : Not installed" "Info"
            }
        } catch {
            Write-ColorOutput "$package : Not installed" "Info"
        }
    }

    Write-Host ""

    # Show rnstatus if available
    if (Get-Command rnstatus -ErrorAction SilentlyContinue) {
        Write-Host "Network Status:" -ForegroundColor Cyan
        rnstatus
    }

    pause
}

function Start-RNSDaemon {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Starting rnsd Daemon"

    if (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue) {
        Write-ColorOutput "rnsd is already running" "Warning"
        return
    }

    Write-ColorOutput "Starting rnsd daemon..." "Progress"

    try {
        Start-Process -FilePath "rnsd" -ArgumentList "--daemon" -NoNewWindow
        Start-Sleep -Seconds 2

        if (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue) {
            Write-ColorOutput "rnsd daemon started successfully" "Success"
        } else {
            Write-ColorOutput "rnsd daemon failed to start" "Error"
        }
    } catch {
        Write-ColorOutput "Failed to start rnsd: $_" "Error"
    }

    pause
}

function Stop-RNSDaemon {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Stopping rnsd Daemon"

    $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue

    if (-not $rnsdProcess) {
        Write-ColorOutput "rnsd is not running" "Warning"
        return
    }

    Write-ColorOutput "Stopping rnsd daemon..." "Progress"

    try {
        Stop-Process -Name "rnsd" -Force
        Start-Sleep -Seconds 2

        if (-not (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue)) {
            Write-ColorOutput "rnsd daemon stopped" "Success"
        } else {
            Write-ColorOutput "Failed to stop rnsd daemon" "Error"
        }
    } catch {
        Write-ColorOutput "Error stopping rnsd: $_" "Error"
    }

    # Honesty: if keep-alive auto-start is enabled, the task will bring rnsd back.
    if (Get-ScheduledTask -TaskName $Script:RnsdTaskName -ErrorAction SilentlyContinue) {
        Write-ColorOutput "Note: rnsd auto-start (keep-alive) is enabled — it will restart on failure / at next logon." "Warning"
        Write-Host "  To keep rnsd stopped, disable auto-start first (Services > 12)." -ForegroundColor Yellow
    }

    pause
}

function Invoke-NetworkTool {
    param([string]$Tool)

    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "$Tool not installed. Install RNS first (option 1)." "Error"
        pause
        return
    }

    switch ($Tool) {
        "rnstatus" {
            Show-Section "Network Status (rnstatus)"
            & rnstatus 2>&1
        }
        "rnpath" {
            Show-Section "Path Table (rnpath)"
            & rnpath -t 2>&1
        }
        "rnprobe" {
            Show-Section "Probe Destination (rnprobe)"
            $dest = Read-Host "Enter destination hash"
            if ($dest) {
                & rnprobe $dest 2>&1
            }
        }
    }

    pause
}

function Invoke-IdentityManagement {
    Show-Section "Identity Management (rnid)"

    if (-not (Get-Command rnid -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rnid not installed. Install RNS first." "Error"
        pause
        return
    }

    Write-Host "  1) Show identity hash"
    Write-Host "  2) Generate new identity"
    Write-Host "  3) View identity file location"
    Write-Host "  0) Back"
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            & rnid 2>&1
        }
        "2" {
            $identityDir = Join-Path $env:USERPROFILE ".reticulum\identities"
            if (-not (Test-Path $identityDir)) {
                New-Item -ItemType Directory -Path $identityDir -Force | Out-Null
            }
            $name = Read-Host "Identity name (e.g., mynode)"
            if ($name) {
                $identityPath = Join-Path $identityDir $name
                & rnid --generate "$identityPath" 2>&1
            }
        }
        "3" {
            $identityDir = Join-Path $env:USERPROFILE ".reticulum\identities"
            Write-Host "Identity files location: $identityDir" -ForegroundColor Cyan
            if (Test-Path $identityDir) {
                Get-ChildItem $identityDir -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-Host "  $($_.Name)"
                }
            } else {
                Write-Host "  (no identities directory yet)"
            }
        }
        "0" { return }
    }

    pause
}

function Invoke-FileTransfer {
    Show-Section "File Transfer (rncp)"

    if (-not (Get-Command rncp -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rncp not installed. Install RNS first." "Error"
        pause
        return
    }

    Write-Host "  1) Send file"
    Write-Host "  2) Listen for incoming transfers"
    Write-Host "  0) Back"
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            $filePath = Read-Host "File path to send"
            if (-not (Test-Path $filePath)) {
                Write-ColorOutput "File not found: $filePath" "Error"
                pause
                return
            }
            $dest = Read-Host "Destination hash"
            if ($dest) {
                Write-ColorOutput "Sending file..." "Progress"
                & rncp "$filePath" "$dest" 2>&1
            }
        }
        "2" {
            Write-ColorOutput "Listening for incoming file transfers..." "Info"
            Write-ColorOutput "Press Ctrl+C to stop listening" "Info"
            & rncp --listen 2>&1
        }
        "0" { return }
    }

    pause
}

function Invoke-RemoteCommand {
    Show-Section "Remote Command (rnx)"

    if (-not (Get-Command rnx -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "rnx not installed. Install RNS first." "Error"
        pause
        return
    }

    $dest = Read-Host "Destination hash"
    if (-not $dest) {
        Write-ColorOutput "No destination specified" "Error"
        pause
        return
    }

    $command = Read-Host "Command to execute"
    if ($command) {
        Write-ColorOutput "Executing remote command..." "Progress"
        & rnx "$dest" "$command" 2>&1
    }

    pause
}

function Enable-RnsdAutoStart {
    Show-Section "Enable rnsd Auto-Start (keep-alive)"

    $rnsdPath = (Get-Command rnsd -ErrorAction SilentlyContinue).Source
    if (-not $rnsdPath) {
        Write-ColorOutput "rnsd not found. Install RNS first." "Error"
        Write-Host "  Tip: Diagnostics > RNS Environment Doctor checks whether rnsd is on PATH." -ForegroundColor Yellow
        pause
        return
    }

    try {
        $taskName = $Script:RnsdTaskName

        # Check if task already exists
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-ColorOutput "Auto-start task already exists" "Warning"
            $replace = Read-Host "Replace existing task? (y/N)"
            if ($replace -ne 'y' -and $replace -ne 'Y') {
                pause
                return
            }
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        $action = New-ScheduledTaskAction -Execute $rnsdPath -Argument "--daemon"
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        # Watchdog: restart up to 3x at 1-minute intervals if rnsd exits unexpectedly.
        # No execution time limit (it is a long-running daemon); single instance only.
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings `
            -Description "Auto-start rnsd at logon with restart-on-failure" | Out-Null
        Write-ColorOutput "Auto-start enabled: rnsd starts at logon and restarts on failure" "Success"
        Write-RnsLog "Enabled rnsd keep-alive task via Task Scheduler" "INFO"

        # Offer to start it now so it can be tested without logging off.
        $now = Read-Host "Start rnsd now via the task? (Y/n)"
        if ($now -ne 'n' -and $now -ne 'N') {
            Start-ScheduledTask -TaskName $taskName
            Start-Sleep -Seconds 2
            if (Get-Process -Name "rnsd" -ErrorAction SilentlyContinue) {
                Write-ColorOutput "rnsd is running" "Success"
            } else {
                Write-ColorOutput "rnsd not detected yet — give it a few seconds" "Warning"
            }
        }
    } catch {
        Write-ColorOutput "Failed to create auto-start task: $_" "Error"
    }

    pause
}

function Disable-RnsdAutoStart {
    Show-Section "Disable rnsd Auto-Start"

    $taskName = $Script:RnsdTaskName
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-ColorOutput "Auto-start disabled" "Success"
        Write-RnsLog "Disabled rnsd auto-start" "INFO"
    } else {
        Write-ColorOutput "No auto-start task found" "Info"
    }

    pause
}

function Enable-MeshChatXAutoStart {
    Show-Section "Enable MeshChatX Auto-Start (keep-alive)"

    $mcxPath = (Get-Command meshchatx -ErrorAction SilentlyContinue).Source
    if (-not $mcxPath) {
        Write-ColorOutput "meshchatx not found. Install MeshChatX first (main menu 'm')." "Error"
        Write-Host "  Tip: Diagnostics > RNS Environment Doctor checks whether meshchatx is on PATH." -ForegroundColor Yellow
        pause
        return
    }

    try {
        $taskName = $Script:MeshChatXTaskName

        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-ColorOutput "MeshChatX auto-start task already exists" "Warning"
            $replace = Read-Host "Replace existing task? (y/N)"
            if ($replace -ne 'y' -and $replace -ne 'Y') {
                pause
                return
            }
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        $action = New-ScheduledTaskAction -Execute $mcxPath -Argument "--headless"
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings `
            -Description "Auto-start MeshChatX (headless web UI) at logon with restart-on-failure" | Out-Null
        Write-ColorOutput "Auto-start enabled: MeshChatX serves https://127.0.0.1:8000 at logon" "Success"
        Write-RnsLog "Enabled MeshChatX keep-alive task via Task Scheduler" "INFO"

        $now = Read-Host "Start MeshChatX now via the task? (Y/n)"
        if ($now -ne 'n' -and $now -ne 'N') {
            Start-ScheduledTask -TaskName $taskName
            Write-ColorOutput "Started — open https://127.0.0.1:8000 (self-signed cert; browser will warn)" "Info"
        }
    } catch {
        Write-ColorOutput "Failed to create MeshChatX auto-start task: $_" "Error"
    }

    pause
}

function Disable-MeshChatXAutoStart {
    Show-Section "Disable MeshChatX Auto-Start"

    $taskName = $Script:MeshChatXTaskName
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-ColorOutput "MeshChatX auto-start disabled" "Success"
        Write-RnsLog "Disabled MeshChatX auto-start" "INFO"
    } else {
        Write-ColorOutput "No MeshChatX auto-start task found" "Info"
    }

    pause
}

function Get-RnsAutoStartStatus {
    Show-Section "Auto-Start Status"

    $tasks = @(
        @{ Name = $Script:RnsdTaskName;      Label = "rnsd" },
        @{ Name = $Script:MeshChatXTaskName; Label = "MeshChatX" }
    )
    foreach ($t in $tasks) {
        $task = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($task) {
            Write-ColorOutput "$($t.Label): auto-start ENABLED (state: $($task.State))" "Success"
            $info = Get-ScheduledTaskInfo -TaskName $t.Name -ErrorAction SilentlyContinue
            if ($info -and $info.LastRunTime) {
                Write-Host "    Last run: $($info.LastRunTime)   Last result: $($info.LastTaskResult)"
            }
        } else {
            Write-Host "  $($t.Label): auto-start disabled" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  Keep-alive restarts the process up to 3x (1-min intervals) if it exits unexpectedly." -ForegroundColor Cyan
    Write-Host "  To keep a service stopped, disable its auto-start first." -ForegroundColor Cyan
    pause
}

function Show-ServiceMenu {
    while ($true) {
        Show-Section "Service Management"

        $rnsdProcess = Get-Process -Name "rnsd" -ErrorAction SilentlyContinue

        Write-Host "  rnsd: " -NoNewline
        if ($rnsdProcess) {
            Write-Host "Running (PID $($rnsdProcess.Id))" -ForegroundColor Green
        } else {
            Write-Host "Stopped" -ForegroundColor Yellow
        }

        $rnsdAuto = Get-ScheduledTask -TaskName $Script:RnsdTaskName -ErrorAction SilentlyContinue
        Write-Host "  Auto-start (keep-alive): " -NoNewline
        if ($rnsdAuto) {
            Write-Host "Enabled" -ForegroundColor Green
        } else {
            Write-Host "Disabled" -ForegroundColor Yellow
        }
        Write-Host ""

        Write-Host "  --- Daemon Control ---" -ForegroundColor Cyan
        Write-Host "   1) Start rnsd daemon"
        Write-Host "   2) Stop rnsd daemon"
        Write-Host "   3) Restart rnsd daemon"
        Write-Host "   4) View detailed status"
        Write-Host ""
        Write-Host "  --- Network Tools ---" -ForegroundColor Cyan
        Write-Host "   5) View network statistics (rnstatus)"
        Write-Host "   6) View path table (rnpath)"
        Write-Host "   7) Probe destination (rnprobe)"
        Write-Host "   8) Transfer file (rncp)"
        Write-Host "   9) Remote command (rnx)"
        Write-Host ""
        Write-Host "  --- Identity & Auto-Start ---" -ForegroundColor Cyan
        Write-Host "  10) Identity management (rnid)"
        Write-Host "  11) Enable rnsd auto-start (keep-alive)"
        Write-Host "  12) Disable rnsd auto-start"
        Write-Host "  13) Enable MeshChatX auto-start (keep-alive)"
        Write-Host "  14) Disable MeshChatX auto-start"
        Write-Host "  15) Auto-start status"
        Write-Host ""
        Write-Host "   0) Back to Main Menu"
        Write-Host ""

        $choice = Read-Host "Select option"

        switch ($choice) {
            "1"  { Start-RNSDaemon }
            "2"  { Stop-RNSDaemon }
            "3"  { Stop-RNSDaemon; Start-RNSDaemon }
            "4"  { Show-Status }
            "5"  { Invoke-NetworkTool "rnstatus" }
            "6"  { Invoke-NetworkTool "rnpath" }
            "7"  { Invoke-NetworkTool "rnprobe" }
            "8"  { Invoke-FileTransfer }
            "9"  { Invoke-RemoteCommand }
            "10" { Invoke-IdentityManagement }
            "11" { Enable-RnsdAutoStart }
            "12" { Disable-RnsdAutoStart }
            "13" { Enable-MeshChatXAutoStart }
            "14" { Disable-MeshChatXAutoStart }
            "15" { Get-RnsAutoStartStatus }
            "0"  { return }
            ""   { return }
            default { Write-ColorOutput "Invalid option" "Error"; Start-Sleep -Seconds 1 }
        }
    }
}
