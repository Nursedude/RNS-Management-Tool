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

    # Get pip command
    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    # Install RNS
    Write-ColorOutput "Installing RNS (Reticulum Network Stack)..." "Progress"
    & $pip install rns --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "RNS installed successfully" "Success"
    } else {
        Write-ColorOutput "Failed to install RNS" "Error"
        return
    }

    # Install LXMF
    Write-ColorOutput "Installing LXMF..." "Progress"
    & $pip install lxmf --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "LXMF installed successfully" "Success"
    } else {
        Write-ColorOutput "Failed to install LXMF" "Error"
    }

    # Ask about NomadNet
    $installNomad = Read-Host "Install NomadNet (terminal client)? (Y/n)"
    if ($installNomad -ne 'n' -and $installNomad -ne 'N') {
        Write-ColorOutput "Installing NomadNet..." "Progress"
        & $pip install nomadnet --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

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
            $pip = "pip"
            if (Get-Command pip3 -ErrorAction SilentlyContinue) {
                $pip = "pip3"
            }

            & $pip install rns --upgrade

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
                    wsl -d $distros[0] -- bash -c "curl -fsSL https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh | bash -s -- --rnode"
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
                $pip = "pip"
                if (Get-Command pip3 -ErrorAction SilentlyContinue) {
                    $pip = "pip3"
                }
                & $pip install sbapp
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

    $pip = "pip"
    if (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pip = "pip3"
    }

    & $pip install nomadnet --upgrade 2>&1 | Out-File -FilePath $Script:LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "NomadNet installed successfully" "Success"
        Write-Host ""
        Write-Host "Run 'nomadnet' to start the terminal client" -ForegroundColor Yellow
    } else {
        Write-ColorOutput "Failed to install NomadNet" "Error"
    }

    pause
}

function Install-MeshChat {
    Show-Section "Installing MeshChat"

    # Check for Node.js / npm
    $npm = Get-Command npm -ErrorAction SilentlyContinue

    if (-not $npm) {
        Write-ColorOutput "Node.js/npm not found" "Error"
        Write-Host ""
        Write-Host "MeshChat requires Node.js 18+. Install options:" -ForegroundColor Yellow
        Write-Host "  1) Download from https://nodejs.org/" -ForegroundColor Cyan
        Write-Host "  2) Install via winget: winget install OpenJS.NodeJS.LTS" -ForegroundColor Cyan
        Write-Host ""
        $installChoice = Read-Host "Install via winget now? (Y/n)"
        if ($installChoice -ne 'n' -and $installChoice -ne 'N') {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-ColorOutput "Installing Node.js LTS via winget..." "Progress"
                winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
                # Refresh PATH
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $npm = Get-Command npm -ErrorAction SilentlyContinue
                if (-not $npm) {
                    Write-ColorOutput "npm still not found after install. Restart your terminal and try again." "Error"
                    pause
                    return
                }
            } else {
                Write-ColorOutput "winget not available. Please install Node.js manually." "Error"
                pause
                return
            }
        } else {
            pause
            return
        }
    } else {
        $nodeVersion = & node --version 2>&1
        Write-ColorOutput "Node.js detected: $nodeVersion" "Success"
        # Check minimum version (18+)
        if ($nodeVersion -match 'v(\d+)') {
            $majorVersion = [int]$Matches[1]
            if ($majorVersion -lt 18) {
                Write-ColorOutput "Node.js $nodeVersion is too old. MeshChat requires Node.js 18+." "Error"
                Write-Host "  Fix: winget install OpenJS.NodeJS.LTS" -ForegroundColor Yellow
                pause
                return
            }
        }
    }

    # Check for git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "git not found. Install via: winget install Git.Git" "Error"
        pause
        return
    }

    $meshchatDir = Join-Path $env:USERPROFILE "reticulum-meshchat"
    $isUpdate = $false

    if (Test-Path $meshchatDir) {
        Write-ColorOutput "MeshChat directory already exists at $meshchatDir" "Warning"
        $update = Read-Host "Update existing installation? (Y/n)"
        if ($update -eq 'n' -or $update -eq 'N') {
            pause
            return
        }
        $isUpdate = $true
    }

    try {
        # Step 1: Clone or update
        if ($isUpdate) {
            Write-ColorOutput "Step 1/4: Updating repository..." "Progress"
            Push-Location $meshchatDir
            & git pull origin main 2>&1 | Out-File -FilePath $Script:LogFile -Append
        } else {
            Write-ColorOutput "Step 1/4: Cloning repository..." "Progress"
            & git clone https://github.com/liamcottle/reticulum-meshchat.git $meshchatDir 2>&1 | Out-File -FilePath $Script:LogFile -Append
            Push-Location $meshchatDir
        }

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Failed to clone/update MeshChat repository" "Error"
            Pop-Location
            pause
            return
        }

        # Step 2: npm install
        Write-ColorOutput "Step 2/4: Installing npm dependencies..." "Progress"
        & npm install 2>&1 | Out-File -FilePath $Script:LogFile -Append

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "npm install failed" "Error"
            Pop-Location
            pause
            return
        }

        # Step 3: Security audit (non-fatal)
        Write-ColorOutput "Step 3/4: Running security audit..." "Progress"
        & npm audit fix --audit-level=moderate 2>&1 | Out-File -FilePath $Script:LogFile -Append

        # Step 4: Build
        Write-ColorOutput "Step 4/4: Building application..." "Progress"
        & npm run build 2>&1 | Out-File -FilePath $Script:LogFile -Append

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Build failed" "Error"
            Pop-Location
            pause
            return
        }

        # Verify
        $packageJson = Join-Path $meshchatDir "package.json"
        if (Test-Path $packageJson) {
            $pkg = Get-Content $packageJson -Raw | ConvertFrom-Json
            Write-ColorOutput "MeshChat v$($pkg.version) installed successfully" "Success"
            Write-Host ""
            Write-Host "Start MeshChat with:" -ForegroundColor Yellow
            Write-Host "  cd $meshchatDir && npm start" -ForegroundColor Cyan
            Write-RnsLog "MeshChat installed: $($pkg.version)" "INFO"
        }

        Pop-Location
    }
    catch {
        Write-ColorOutput "MeshChat installation failed: $_" "Error"
        Pop-Location -ErrorAction SilentlyContinue
    }

    pause
}

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
