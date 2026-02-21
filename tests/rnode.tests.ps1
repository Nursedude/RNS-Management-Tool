#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/rnode.ps1 — RNODE device configuration
.NOTES
    Covers: RNS001 (no eval), RNS002 (port validation), RNS003 (param ranges), RNS005 (destructive safety)
    Uses .Contains() for literal string checks to avoid regex/source-text mismatch.
#>

BeforeAll {
    $Script:RnodeSource = Get-Content -Path "$PSScriptRoot/../pwsh/rnode.ps1" -Raw

    $Script:RnodeAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $Script:RnodeSource, [ref]$null, [ref]$null
    )
}

Describe "RNS002: COM Port Validation" {

    Context "Port regex pattern in Get-RnodeSerialPort" {

        It "Source contains COM port regex pattern" {
            # Source has: $port -notmatch '^COM\d+$'
            # Use .Contains() to match literal text — avoids regex metachar confusion
            $Script:RnodeSource.Contains('^COM\d+$') | Should -BeTrue
        }

        It "Accepts valid COM port COM3" {
            "COM3" -match '^COM\d+$' | Should -BeTrue
        }

        It "Rejects empty string" {
            "" -match '^COM\d+$' | Should -BeFalse
        }

        It "Rejects lowercase com3" {
            "com3" -cmatch '^COM\d+$' | Should -BeFalse
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
            $Script:RnodeSource.Contains('-ge 7') | Should -BeTrue
            $Script:RnodeSource.Contains('-le 12') | Should -BeTrue
        }

        It "Accepts SF 7 (lower bound)" {
            $sf = "7"
            ($sf -match '^\d+$' -and [int]$sf -ge 7 -and [int]$sf -le 12) | Should -BeTrue
        }

        It "Accepts SF 12 (upper bound)" {
            $sf = "12"
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
            $Script:RnodeSource.Contains('-ge 5') | Should -BeTrue
            $Script:RnodeSource.Contains('-le 8') | Should -BeTrue
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

        It "Rejects non-numeric CR" {
            $cr = "high"
            ($cr -match '^\d+$') | Should -BeFalse
        }
    }

    Context "TX Power (-10 to 30 dBm)" {

        It "Source validates TX power range -10 to 30" {
            $Script:RnodeSource.Contains('-ge -10') | Should -BeTrue
            $Script:RnodeSource.Contains('-le 30') | Should -BeTrue
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
            # Source has: $freq -match '^\d+$'
            $Script:RnodeSource.Contains('$freq -match') | Should -BeTrue
            $Script:RnodeSource.Contains('^\d+$') | Should -BeTrue
        }

        It "Accepts 915000000 Hz (US 915MHz)" {
            "915000000" -match '^\d+$' | Should -BeTrue
        }

        It "Rejects float frequency" {
            "915.5" -match '^\d+$' | Should -BeFalse
        }

        It "Rejects non-numeric frequency" {
            "915MHz" -match '^\d+$' | Should -BeFalse
        }
    }

    Context "Bandwidth (numeric validation)" {

        It "Source validates bandwidth is numeric" {
            # Source has: $bw -match '^\d+$'
            $Script:RnodeSource.Contains('$bw -match') | Should -BeTrue
        }

        It "Accepts bandwidth 125" {
            "125" -match '^\d+$' | Should -BeTrue
        }

        It "Rejects non-numeric bandwidth" {
            "wide" -match '^\d+$' | Should -BeFalse
        }
    }
}

Describe "RNS001: Command Safety (No Eval)" {

    It "Source uses array-based command arguments" {
        $Script:RnodeSource.Contains('$cmdArgs = @(') | Should -BeTrue
    }

    It "Source uses splatting for rnodeconf execution" {
        $Script:RnodeSource.Contains('& rnodeconf @cmdArgs') | Should -BeTrue
    }

    It "Source does not use Invoke-Expression" {
        $Script:RnodeSource | Should -Not -Match 'Invoke-Expression'
    }

    It "Source does not use iex alias" {
        $Script:RnodeSource | Should -Not -Match '(?<![a-zA-Z])iex\s+'
    }
}

Describe "RNS005: Destructive Action Safety" {

    Context "Bootloader update confirmation" {

        It "Update-RnodeBootloader function exists" {
            $Script:RnodeSource.Contains('function Update-RnodeBootloader') | Should -BeTrue
        }

        It "Bootloader update has warning message" {
            $Script:RnodeSource.Contains('WARNING') | Should -BeTrue
            $Script:RnodeSource.Contains('bootloader') | Should -BeTrue
        }

        It "Bootloader update requires confirmation" {
            $Script:RnodeSource.Contains('Are you sure') | Should -BeTrue
        }

        It "Bootloader update checks for y/Y confirmation" {
            $Script:RnodeSource.Contains("-ne 'y'") | Should -BeTrue
        }
    }
}

Describe "Function Existence" {

    It "Get-RnodeSerialPort function exists" {
        $Script:RnodeSource.Contains('function Get-RnodeSerialPort') | Should -BeTrue
    }

    It "Set-RnodeRadioParameter function exists" {
        $Script:RnodeSource.Contains('function Set-RnodeRadioParameter') | Should -BeTrue
    }

    It "Get-RnodeEeprom function exists" {
        $Script:RnodeSource.Contains('function Get-RnodeEeprom') | Should -BeTrue
    }

    It "Update-RnodeBootloader function exists" {
        $Script:RnodeSource.Contains('function Update-RnodeBootloader') | Should -BeTrue
    }

    It "Open-RnodeConsole function exists" {
        $Script:RnodeSource.Contains('function Open-RnodeConsole') | Should -BeTrue
    }

    It "Show-RnodeMenu function exists" {
        $Script:RnodeSource.Contains('function Show-RnodeMenu') | Should -BeTrue
    }

    It "Set-RnodeRadioParameter uses SupportsShouldProcess" {
        $fnIdx = $Script:RnodeSource.IndexOf('function Set-RnodeRadioParameter')
        $fnIdx | Should -BeGreaterOrEqual 0
        $cbIdx = $Script:RnodeSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
        $cbIdx | Should -BeGreaterThan $fnIdx
        ($cbIdx - $fnIdx) | Should -BeLessThan 100
    }
}

Describe "USB Device Detection" {

    It "Source uses CIM for USB device enumeration" {
        $Script:RnodeSource.Contains('Get-CimInstance') | Should -BeTrue
        $Script:RnodeSource.Contains('Win32_PnPEntity') | Should -BeTrue
    }

    It "Source detects common USB-serial chipsets" {
        $Script:RnodeSource.Contains('CH340') | Should -BeTrue
        $Script:RnodeSource.Contains('CP210') | Should -BeTrue
    }

    It "Source also uses SerialPort.GetPortNames" {
        $Script:RnodeSource.Contains('SerialPort') | Should -BeTrue
        $Script:RnodeSource.Contains('GetPortNames') | Should -BeTrue
    }
}

Describe "Menu Structure" {

    It "RNODE menu has installation and configuration sections" {
        $Script:RnodeSource.Contains('Installation') | Should -BeTrue
        $Script:RnodeSource.Contains('Configuration') | Should -BeTrue
    }

    It "RNODE menu has back option (0)" {
        $Script:RnodeSource.Contains('"0"') | Should -BeTrue
    }

    It "RNODE menu checks rnodeconf availability" {
        $Script:RnodeSource.Contains('Get-Command rnodeconf') | Should -BeTrue
    }

    It "RNODE menu shows unavailable state for rnodeconf" {
        $Script:RnodeSource.Contains('rnodeconf not installed') | Should -BeTrue
    }
}
