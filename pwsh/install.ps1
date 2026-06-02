#########################################################
# pwsh/install.ps1 — Installation functions
# Dot-sourced by rns_management_tool.ps1
#########################################################

function Install-Python {
    Show-Section "Installing Python"

    Write-ColorOutput "Python installation options:" "Info"
    Write-Host ""
    Write-Host "  1) Download from Microsoft Store (Recommended)"
    Write-Host "  2) Download from python.org"
    Write-Host "  3) Install via winget"
    Write-Host "  0) Cancel"
    Write-Host ""

    $choice = Read-Host "Select installation method"

    switch ($choice) {
        "1" {
            Write-ColorOutput "Opening Microsoft Store..." "Info"
            Start-Process "ms-windows-store://pdp/?ProductId=9NRWMJP3717K"
            Write-ColorOutput "Please install Python from the Microsoft Store and run this script again" "Warning"
            pause
        }
        "2" {
            Write-ColorOutput "Opening python.org download page..." "Info"
            Start-Process "https://www.python.org/downloads/"
            Write-ColorOutput "Please download and install Python, then run this script again" "Warning"
            pause
        }
        "3" {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-ColorOutput "Installing Python via winget..." "Progress"
                winget install Python.Python.3.11
                Write-ColorOutput "Python installation completed" "Success"
            } else {
                Write-ColorOutput "winget not available on this system" "Error"
            }
        }
        default {
            Write-ColorOutput "Installation cancelled" "Warning"
        }
    }
}

function Install-Reticulum {
    param([bool]$UseWSL = $false)

    if ($UseWSL) {
        Install-ReticulumWSL
        return
    }

    Show-Section "Installing Reticulum Ecosystem"

    if (-not (Test-Python)) {
        Write-ColorOutput "Python is required but not installed" "Error"
        $install = Read-Host "Would you like to install Python now? (Y/n)"
        if ($install -ne 'n' -and $install -ne 'N') {
            Install-Python
            return
        }
    }

    Write-ColorOutput "Installing Reticulum components..." "Progress"

    # Verify pip is available
    $pip = Get-PipCommand
    if (-not $pip) {
        Write-ColorOutput "pip not found. Trying python -m pip as fallback..." "Warning"
    }

    # Install RNS
    Write-ColorOutput "Installing RNS (Reticulum Network Stack)..." "Progress"
    Invoke-Pip install rns --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "RNS installed successfully" "Success"
    } else {
        Write-ColorOutput "Failed to install RNS" "Error"
        return
    }

    # Install LXMF
    Write-ColorOutput "Installing LXMF..." "Progress"
    Invoke-Pip install lxmf --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "LXMF installed successfully" "Success"
    } else {
        Write-ColorOutput "Failed to install LXMF" "Error"
    }

    # Ask about NomadNet
    $installNomad = Read-Host "Install NomadNet (terminal client)? (Y/n)"
    if ($installNomad -ne 'n' -and $installNomad -ne 'N') {
        Write-ColorOutput "Installing NomadNet..." "Progress"
        Invoke-Pip install nomadnet --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "NomadNet installed successfully" "Success"
        } else {
            Write-ColorOutput "Failed to install NomadNet" "Error"
        }
    }

    Write-ColorOutput "Reticulum installation completed" "Success"
}

function Install-ReticulumWSL {
    Show-Section "Installing Reticulum in WSL"

    $distros = Get-WSLDistribution
    if ($distros.Count -eq 0) {
        Write-ColorOutput "No WSL distributions found" "Error"
        Write-ColorOutput "Install WSL first with: wsl --install" "Info"
        return
    }

    Write-Host "Available WSL distributions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $distros.Count; $i++) {
        Write-Host "  $($i + 1)) $($distros[$i])"
    }
    Write-Host ""

    $selection = Read-Host "Select distribution"
    $selectedDistro = $distros[[int]$selection - 1]

    if (-not $selectedDistro) {
        Write-ColorOutput "Invalid selection" "Error"
        return
    }

    Write-ColorOutput "Installing Reticulum in $selectedDistro..." "Progress"

    # Download the Linux script to WSL
    $scriptUrl = "https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh"
    $wslScript = "/tmp/rns_management_tool.sh"

    wsl -d $selectedDistro -- bash -c "curl -fsSL $scriptUrl -o $wslScript && chmod +x $wslScript"

    # Run the installer
    Write-ColorOutput "Launching installer in WSL..." "Info"
    wsl -d $selectedDistro -- bash -c "/tmp/rns_management_tool.sh"
}

function Install-RNODE {
    Show-Section "RNODE Installation"

    Write-Host "RNODE installation options:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Install via Python (Native Windows)"
    Write-Host "  2) Install via WSL (Recommended for USB devices)"
    Write-Host "  3) Use Web Flasher"
    Write-Host "  0) Back"
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            Write-ColorOutput "Installing rnodeconf..." "Progress"
            Invoke-Pip install rns --upgrade

            if (Get-Command rnodeconf -ErrorAction SilentlyContinue) {
                Write-ColorOutput "rnodeconf installed successfully" "Success"
                Write-Host ""
                Write-Host "Run 'rnodeconf --help' for usage information" -ForegroundColor Yellow
            } else {
                Write-ColorOutput "rnodeconf installation failed" "Error"
            }
        }
        "2" {
            if (Test-WSL) {
                Write-ColorOutput "Launching RNODE installer in WSL..." "Info"
                $distros = Get-WSLDistribution
                if ($distros.Count -gt 0) {
                    # Download to temp file before execution (avoids partial-download risk of curl|bash)
                    wsl -d $distros[0] -- bash -c "tmpscript=`$(mktemp `${TMPDIR:-/tmp}/rns_mgmt_XXXXXX.sh) && curl -fsSL -o `$tmpscript 'https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh' && [ -s `$tmpscript ] && bash `$tmpscript --rnode; rm -f `$tmpscript"
                }
            } else {
                Write-ColorOutput "WSL not available" "Error"
                Write-ColorOutput "Install WSL with: wsl --install" "Info"
            }
        }
        "3" {
            Write-ColorOutput "Opening RNode Web Flasher..." "Info"
            Start-Process "https://github.com/liamcottle/rnode-flasher"
        }
    }

    pause
}

function Install-Sideband {
    Show-Section "Installing Sideband"

    Write-ColorOutput "Sideband is available for Windows as an executable" "Info"
    Write-Host ""
    Write-Host "Download options:" -ForegroundColor Cyan
    Write-Host "  1) Download Windows executable"
    Write-Host "  2) Install from source (requires Python)"
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            Write-ColorOutput "Opening Sideband releases page..." "Info"
            Start-Process "https://github.com/markqvist/Sideband/releases"
        }
        "2" {
            if (Test-Python) {
                Write-ColorOutput "Installing Sideband from source..." "Progress"
                Invoke-Pip install sbapp
            } else {
                Write-ColorOutput "Python not found" "Error"
            }
        }
    }

    pause
}

function Install-NomadNet {
    Show-Section "Installing NomadNet"

    if (-not (Test-Python)) {
        Write-ColorOutput "Python is required but not installed" "Error"
        $install = Read-Host "Would you like to install Python now? (Y/n)"
        if ($install -ne 'n' -and $install -ne 'N') {
            Install-Python
            return
        }
    }

    Write-ColorOutput "Installing NomadNet terminal client..." "Progress"

    Invoke-Pip install nomadnet --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "NomadNet installed successfully" "Success"
        Write-Host ""
        Write-Host "Run 'nomadnet' to start the terminal client" -ForegroundColor Yellow
    } else {
        Write-ColorOutput "Failed to install NomadNet" "Error"
    }

    pause
}

function Install-MeshChatX {
    Show-Section "Installing MeshChatX"

    Write-Host "MeshChatX (Quad4 Software) is the actively maintained successor to" -ForegroundColor Cyan
    Write-Host "the original Reticulum MeshChat. It installs as a pip wheel with the" -ForegroundColor Cyan
    Write-Host "frontend bundled, so no Node.js build is required." -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Python)) {
        Write-ColorOutput "Python is required but not installed" "Error"
        $install = Read-Host "Would you like to install Python now? (Y/n)"
        if ($install -ne 'n' -and $install -ne 'N') {
            Install-Python
            return
        }
        pause
        return
    }

    # Python >=3.11 gate — MeshChatX declares requires-python>=3.11.
    $pyVer = & python -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
    $pyOk = & python -c "import sys; print(1 if sys.version_info >= (3, 11) else 0)" 2>$null
    if ($pyOk -ne '1') {
        Write-ColorOutput "MeshChatX requires Python 3.11+ (found $pyVer)" "Error"
        Write-Host "  Install a newer Python from https://www.python.org/downloads/ and retry." -ForegroundColor Yellow
        pause
        return
    }

    # Legacy migration — offer to remove the old git/npm MeshChat tree.
    $legacyDir = Join-Path $env:USERPROFILE "reticulum-meshchat"
    if (Test-Path $legacyDir) {
        Write-ColorOutput "Found old git-based MeshChat at $legacyDir (deprecated)" "Warning"
        $remove = Read-Host "Remove it to reclaim disk space? (Y/n)"
        if ($remove -ne 'n' -and $remove -ne 'N') {
            Remove-Item -Recurse -Force $legacyDir -ErrorAction SilentlyContinue
            Write-ColorOutput "Removed legacy MeshChat directory" "Success"
        }
    }

    Write-ColorOutput "Installing reticulum-meshchatx via pip..." "Progress"
    Invoke-Pip install reticulum-meshchatx --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        $ver = "unknown"
        $showOut = Invoke-Pip show reticulum-meshchatx 2>$null | Select-String '^Version:'
        if ($showOut) { $ver = ($showOut.ToString() -split '\s+')[1] }
        Write-ColorOutput "MeshChatX v$ver installed successfully" "Success"
        Write-RnsLog "MeshChatX installed: $ver" "INFO"
        Write-Host ""
        Write-Host "Start MeshChatX:  meshchatx --headless" -ForegroundColor Cyan
        Write-Host "Then open:        https://127.0.0.1:8000  (self-signed cert — browser will warn)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Prefer a native desktop app? Download the Windows installer from:" -ForegroundColor Yellow
        Write-Host "  https://github.com/Quad4-Software/MeshChatX/releases/latest" -ForegroundColor Yellow
    } else {
        Write-ColorOutput "Failed to install MeshChatX" "Error"
        Write-Host "  Check the log (Main Menu > Logs) for pip output." -ForegroundColor Yellow
    }

    pause
}

# Back-compat alias — older menu wiring/tests may still call Install-MeshChat.
function Install-MeshChat { Install-MeshChatX @args }

function Install-Ecosystem {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Show-Section "Reinstalling All Components"

    Write-ColorOutput "WARNING: This will reinstall all Reticulum components" "Warning"
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        return
    }

    New-Backup
    Install-Reticulum -UseWSL $false
    pause
}
