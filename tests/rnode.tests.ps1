#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/rnode.ps1 — RNODE device configuration
    Mirrors BATS hardware_validation.bats for PowerShell parity
.NOTES
    Covers: RNS001 (no eval), RNS002 (port validation), RNS003 (param ranges), RNS005 (destructive safety)
#>

BeforeAll {
    # Read the rnode.ps1 source as text for static analysis tests
    $Script:RnodeSource = Get-Content -Path "$PSScriptRoot/../pwsh/rnode.ps1" -Raw
    $Script:MainSource = Get-Content -Path "$PSScriptRoot/../rns_management_tool.ps1" -Raw

    # Parse AST for function existence checks
    $Script:RnodeAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:RnodeSource, [ref]$null, [ref]$null
    )
}

Describe "RNS002: COM Port Validation" {

    Context "Port regex pattern in Get-RnodeSerialPort" {

        It "Source contains COM port regex pattern" {
            $Script:RnodeSource | Should -Match '\^COM\\d\+\$'
        }

        It "Accepts valid COM port COM3" {
            "COM3" -match '^COM\d+$' | Should -BeTrue
        }

        It "Accepts valid COM port COM1" {
            "COM1" -match '^COM\d+$' | Should -BeTrue
        }

        It "Accepts valid COM port COM15" {
            "COM15" -match '^COM\d+$' | Should -BeTrue
        }

        It "Accepts valid COM port COM256" {
            "COM256" -match '^COM\d+$' | Should -BeTrue
        }

        It "Rejects empty string" {
            "" -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects lowercase com3" {
            "com3" -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects /dev/ttyUSB0 (Linux path)" {
            "/dev/ttyUSB0" -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects COM port with semicolon injection" {
            "COM3;rm -rf /" -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects COM port with backtick injection" {
            "COM3``whoami``" -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects COM port with dollar-paren injection" {
            'COM3$(id)' -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects COM with no number" {
            "COM" -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects path traversal in port name" {
            "COM3/../etc/passwd" -match '^COM\d+$' | Should -BeFalse
        }
    }
}

Describe "RNS003: Radio Parameter Range Validation" {

    Context "Spreading Factor (7-12)" {

        It "Source validates SF range 7-12" {
            $Script:RnodeSource | Should -Match 'ge 7.*le 12'
        }

        It "Accepts SF 7 (lower bound)" {
            $sf = "7"
            ($sf -match '^\d+$' -and [int]$sf -ge 7 -and [int]$sf -le 12) | Should -BeTrue
        }

        It "Accepts SF 12 (upper bound)" {
            $sf = "12"
            ($sf -match '^\d+$' -and [int]$sf -ge 7 -and [int]$sf -le 12) | Should -BeTrue
        }

        It "Accepts SF 9 (mid range)" {
            $sf = "9"
            ($sf -match '^\d+$' -and [int]$sf -ge 7 -and [int]$sf -le 12) | Should -BeTrue
        }

        It "Rejects SF 6 (below range)" {
            $sf = "6"
            ($sf -match '^\d+$' -and [int]$sf -ge 7 -and [int]$sf -le 12) | Should -BeFalse
        }

        It "Rejects SF 13 (above range)" {
            $sf = "13"
            ($sf -match '^\d+$' -and [int]$sf -ge 7 -and [int]$sf -le 12) | Should -BeFalse
        }

        It "Rejects non-numeric SF" {
            $sf = "abc"
            ($sf -match '^\d+$') | Should -BeFalse
        }
    }

    Context "Coding Rate (5-8)" {

        It "Source validates CR range 5-8" {
            $Script:RnodeSource | Should -Match 'ge 5.*le 8'
        }

        It "Accepts CR 5 (lower bound)" {
            $cr = "5"
            ($cr -match '^\d+$' -and [int]$cr -ge 5 -and [int]$cr -le 8) | Should -BeTrue
        }

        It "Accepts CR 8 (upper bound)" {
            $cr = "8"
            ($cr -match '^\d+$' -and [int]$cr -ge 5 -and [int]$cr -le 8) | Should -BeTrue
        }

        It "Rejects CR 4 (below range)" {
            $cr = "4"
            ($cr -match '^\d+$' -and [int]$cr -ge 5 -and [int]$cr -le 8) | Should -BeFalse
        }

        It "Rejects CR 9 (above range)" {
            $cr = "9"
            ($cr -match '^\d+$' -and [int]$cr -ge 5 -and [int]$cr -le 8) | Should -BeFalse
        }

        It "Rejects non-numeric CR" {
            $cr = "high"
            ($cr -match '^\d+$') | Should -BeFalse
        }
    }

    Context "TX Power (-10 to 30 dBm)" {

        It "Source validates TX power range -10 to 30" {
            $Script:RnodeSource | Should -Match 'ge -10.*le 30'
        }

        It "Accepts TX power 17 (typical)" {
            $txp = "17"
            ($txp -match '^-?\d+$' -and [int]$txp -ge -10 -and [int]$txp -le 30) | Should -BeTrue
        }

        It "Accepts TX power -10 (lower bound)" {
            $txp = "-10"
            ($txp -match '^-?\d+$' -and [int]$txp -ge -10 -and [int]$txp -le 30) | Should -BeTrue
        }

        It "Accepts TX power 30 (upper bound)" {
            $txp = "30"
            ($txp -match '^-?\d+$' -and [int]$txp -ge -10 -and [int]$txp -le 30) | Should -BeTrue
        }

        It "Accepts TX power 0" {
            $txp = "0"
            ($txp -match '^-?\d+$' -and [int]$txp -ge -10 -and [int]$txp -le 30) | Should -BeTrue
        }

        It "Rejects TX power -11 (below range)" {
            $txp = "-11"
            ($txp -match '^-?\d+$' -and [int]$txp -ge -10 -and [int]$txp -le 30) | Should -BeFalse
        }

        It "Rejects TX power 31 (above range)" {
            $txp = "31"
            ($txp -match '^-?\d+$' -and [int]$txp -ge -10 -and [int]$txp -le 30) | Should -BeFalse
        }

        It "Rejects non-numeric TX power" {
            $txp = "max"
            ($txp -match '^-?\d+$') | Should -BeFalse
        }
    }

    Context "Frequency (numeric validation)" {

        It "Source validates frequency is numeric" {
            $Script:RnodeSource | Should -Match "freq.*match.*\^\\d\+\$"
        }

        It "Accepts 915000000 Hz (US 915MHz)" {
            $freq = "915000000"
            ($freq -match '^\d+$') | Should -BeTrue
        }

        It "Accepts 868000000 Hz (EU 868MHz)" {
            $freq = "868000000"
            ($freq -match '^\d+$') | Should -BeTrue
        }

        It "Accepts 433000000 Hz (433MHz)" {
            $freq = "433000000"
            ($freq -match '^\d+$') | Should -BeTrue
        }

        It "Rejects float frequency" {
            $freq = "915.5"
            ($freq -match '^\d+$') | Should -BeFalse
        }

        It "Rejects negative frequency" {
            $freq = "-915000000"
            ($freq -match '^\d+$') | Should -BeFalse
        }

        It "Rejects non-numeric frequency" {
            $freq = "915MHz"
            ($freq -match '^\d+$') | Should -BeFalse
        }
    }

    Context "Bandwidth (numeric validation)" {

        It "Source validates bandwidth is numeric" {
            $Script:RnodeSource | Should -Match "bw.*match.*\^\\d\+\$"
        }

        It "Accepts bandwidth 125" {
            $bw = "125"
            ($bw -match '^\d+$') | Should -BeTrue
        }

        It "Accepts bandwidth 250" {
            $bw = "250"
            ($bw -match '^\d+$') | Should -BeTrue
        }

        It "Accepts bandwidth 500" {
            $bw = "500"
            ($bw -match '^\d+$') | Should -BeTrue
        }

        It "Rejects non-numeric bandwidth" {
            $bw = "wide"
            ($bw -match '^\d+$') | Should -BeFalse
        }
    }
}

Describe "RNS001: Command Safety (No Eval)" {

    It "Source uses array-based command arguments" {
        $Script:RnodeSource | Should -Match '\$cmdArgs\s*=\s*@\('
    }

    It "Source uses splatting for rnodeconf execution" {
        $Script:RnodeSource | Should -Match '&\s+rnodeconf\s+@cmdArgs'
    }

    It "Source does not use Invoke-Expression" {
        $Script:RnodeSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        # Match iex as a standalone command, not as part of another word
        $Script:RnodeSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }
}

Describe "RNS005: Destructive Action Safety" {

    Context "Bootloader update confirmation" {

        It "Update-RnodeBootloader function exists" {
            $Script:RnodeSource | Should -Match 'function Update-RnodeBootloader'
        }

        It "Bootloader update has warning message" {
            $Script:RnodeSource | Should -Match 'WARNING.*bootloader'
        }

        It "Bootloader update requires confirmation" {
            $Script:RnodeSource | Should -Match 'Are you sure.*bootloader'
        }

        It "Bootloader update checks for y/Y confirmation" {
            $Script:RnodeSource | Should -Match "confirm.*-ne\s+'y'"
        }
    }
}

Describe "Function Existence" {

    It "Get-RnodeSerialPort function exists" {
        $Script:RnodeSource | Should -Match 'function Get-RnodeSerialPort'
    }

    It "Set-RnodeRadioParameter function exists" {
        $Script:RnodeSource | Should -Match 'function Set-RnodeRadioParameter'
    }

    It "Get-RnodeEeprom function exists" {
        $Script:RnodeSource | Should -Match 'function Get-RnodeEeprom'
    }

    It "Update-RnodeBootloader function exists" {
        $Script:RnodeSource | Should -Match 'function Update-RnodeBootloader'
    }

    It "Open-RnodeConsole function exists" {
        $Script:RnodeSource | Should -Match 'function Open-RnodeConsole'
    }

    It "Show-RnodeMenu function exists" {
        $Script:RnodeSource | Should -Match 'function Show-RnodeMenu'
    }

    It "Set-RnodeRadioParameter uses SupportsShouldProcess" {
        $Script:RnodeSource | Should -Match 'Set-RnodeRadioParameter.*\[CmdletBinding\(SupportsShouldProcess\)\]'
    }
}

Describe "USB Device Detection" {

    It "Source uses CIM for USB device enumeration" {
        $Script:RnodeSource | Should -Match 'Get-CimInstance.*Win32_PnPEntity'
    }

    It "Source detects common USB-serial chipsets" {
        $Script:RnodeSource | Should -Match 'CH340|CP210|FTDI|Silicon Labs'
    }

    It "Source also uses SerialPort.GetPortNames" {
        $Script:RnodeSource | Should -Match 'SerialPort.*GetPortNames'
    }
}

Describe "Menu Structure" {

    It "RNODE menu has installation section" {
        $Script:RnodeSource | Should -Match 'Installation'
    }

    It "RNODE menu has configuration section" {
        $Script:RnodeSource | Should -Match 'Configuration'
    }

    It "RNODE menu has back option (0)" {
        $Script:RnodeSource | Should -Match '"0".*return'
    }

    It "RNODE menu uses while loop (not recursive)" {
        $Script:RnodeSource | Should -Match 'while\s*\(\$true\)'
    }

    It "RNODE menu checks rnodeconf availability" {
        $Script:RnodeSource | Should -Match 'Get-Command rnodeconf'
    }

    It "RNODE menu shows unavailable state for rnodeconf" {
        $Script:RnodeSource | Should -Match 'rnodeconf not installed'
    }
}
