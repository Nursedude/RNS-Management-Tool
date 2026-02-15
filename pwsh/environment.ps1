#########################################################
# pwsh/environment.ps1 — WSL, Python, pip detection
# Dot-sourced by rns_management_tool.ps1
#########################################################

function Test-WSL {
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        try {
            $wslOutput = wsl --list --quiet 2>$null
            if ($wslOutput) {
                return $true
            }
        } catch {
            return $false
        }
    }
    return $false
}

function Get-WSLDistribution {
    if (-not (Test-WSL)) {
        return @()
    }

    try {
        $distros = wsl --list --quiet | Where-Object { $_ -and $_.Trim() }
        return $distros
    } catch {
        return @()
    }
}

function Test-Python {
    Show-Section "Checking Python Installation"

    # Check for Python in PATH
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        $python = Get-Command python3 -ErrorAction SilentlyContinue
    }

    if ($python) {
        $version = & $python.Source --version 2>&1
        Write-ColorOutput "Python detected: $version" "Success"
        return $true
    } else {
        Write-ColorOutput "Python not found in PATH" "Error"
        return $false
    }
}

function Test-Pip {
    $pip = Get-Command pip -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = Get-Command pip3 -ErrorAction SilentlyContinue
    }

    if ($pip) {
        $version = & $pip.Source --version 2>&1
        Write-ColorOutput "pip detected: $version" "Success"
        return $true
    } else {
        Write-ColorOutput "pip not found" "Error"
        return $false
    }
}
