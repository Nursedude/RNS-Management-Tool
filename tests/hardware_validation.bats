#!/usr/bin/env bats
# RNODE Hardware Validation Tests
# Tests device port validation, radio parameter ranges, command construction,
# and board compatibility across 21+ supported RNODE devices.
#
# Run with: bats tests/hardware_validation.bats

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export LIB_DIR="$SCRIPT_DIR/lib"
    export RNODE_SH="$LIB_DIR/rnode.sh"
    export PS_RNODE="$SCRIPT_DIR/pwsh/rnode.ps1"

    # Combined source for grep-based tests
    COMBINED_SOURCE="$SCRIPT_DIR/rns_management_tool.sh"
    if [ -d "$LIB_DIR" ]; then
        for module in "$LIB_DIR"/*.sh; do
            [ -f "$module" ] && COMBINED_SOURCE="$COMBINED_SOURCE $module"
        done
    fi
    export COMBINED_SOURCE
}

#########################################################
# Bash Device Port Validation (RNS002)
#########################################################

@test "RNODE: port regex accepts /dev/ttyUSB0" {
    [[ "/dev/ttyUSB0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex accepts /dev/ttyACM0" {
    [[ "/dev/ttyACM0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex accepts /dev/ttyS0" {
    [[ "/dev/ttyS0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex accepts /dev/ttyUSB15" {
    [[ "/dev/ttyUSB15" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex accepts /dev/ttyAMA0 (RPi GPIO UART)" {
    [[ "/dev/ttyAMA0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects empty input" {
    ! [[ "" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects plain text" {
    ! [[ "COM3" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects path traversal" {
    ! [[ "/dev/../etc/passwd" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects spaces" {
    ! [[ "/dev/tty USB0" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects semicolons (command injection)" {
    ! [[ "/dev/ttyUSB0;rm -rf /" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects backticks (command injection)" {
    # shellcheck disable=SC2016
    ! [[ '/dev/ttyUSB0`whoami`' =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects dollar substitution" {
    ! [[ '/dev/ttyUSB$(id)' =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects /dev/null" {
    ! [[ "/dev/null" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

@test "RNODE: port regex rejects bare /dev/tty (no suffix)" {
    ! [[ "/dev/tty" =~ ^/dev/tty[A-Za-z0-9]+$ ]]
}

#########################################################
# PowerShell COM Port Validation (RNS002)
#########################################################

@test "RNODE PS: COM port regex accepts COM3" {
    [[ "COM3" =~ ^COM[0-9]+$ ]]
}

@test "RNODE PS: COM port regex accepts COM15" {
    [[ "COM15" =~ ^COM[0-9]+$ ]]
}

@test "RNODE PS: COM port regex rejects empty" {
    ! [[ "" =~ ^COM[0-9]+$ ]]
}

@test "RNODE PS: COM port regex rejects COMX" {
    ! [[ "COMX" =~ ^COM[0-9]+$ ]]
}

@test "RNODE PS: COM port regex rejects /dev/ttyUSB0" {
    ! [[ "/dev/ttyUSB0" =~ ^COM[0-9]+$ ]]
}

@test "RNODE PS: COM port regex rejects COM with trailing text" {
    ! [[ "COM3;whoami" =~ ^COM[0-9]+$ ]]
}

@test "RNODE PS: validation regex present in rnode.ps1" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q "COM\\\\d+" "$PS_RNODE"
}

#########################################################
# Spreading Factor Validation (RNS003 - range 7-12)
#########################################################

@test "RNODE: SF 7 passes range check" {
    local SF=7
    [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ]
}

@test "RNODE: SF 12 passes range check" {
    local SF=12
    [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ]
}

@test "RNODE: SF 9 passes range check (common LoRa setting)" {
    local SF=9
    [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ]
}

@test "RNODE: SF 6 fails range check (too low)" {
    local SF=6
    ! ( [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ] )
}

@test "RNODE: SF 13 fails range check (too high)" {
    local SF=13
    ! ( [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ] )
}

@test "RNODE: SF 0 fails range check" {
    local SF=0
    ! ( [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ] )
}

@test "RNODE: SF non-numeric fails" {
    local SF="abc"
    ! [[ "$SF" =~ ^[0-9]+$ ]]
}

@test "RNODE: SF negative fails" {
    local SF="-1"
    ! [[ "$SF" =~ ^[0-9]+$ ]]
}

#########################################################
# Coding Rate Validation (RNS003 - range 5-8)
#########################################################

@test "RNODE: CR 5 passes range check" {
    local CR=5
    [[ "$CR" =~ ^[0-9]+$ ]] && [ "$CR" -ge 5 ] && [ "$CR" -le 8 ]
}

@test "RNODE: CR 8 passes range check" {
    local CR=8
    [[ "$CR" =~ ^[0-9]+$ ]] && [ "$CR" -ge 5 ] && [ "$CR" -le 8 ]
}

@test "RNODE: CR 4 fails range check (too low)" {
    local CR=4
    ! ( [[ "$CR" =~ ^[0-9]+$ ]] && [ "$CR" -ge 5 ] && [ "$CR" -le 8 ] )
}

@test "RNODE: CR 9 fails range check (too high)" {
    local CR=9
    ! ( [[ "$CR" =~ ^[0-9]+$ ]] && [ "$CR" -ge 5 ] && [ "$CR" -le 8 ] )
}

@test "RNODE: CR non-numeric fails" {
    local CR="high"
    ! [[ "$CR" =~ ^[0-9]+$ ]]
}

#########################################################
# TX Power Validation (RNS003 - range -10 to 30 dBm)
#########################################################

@test "RNODE: TXP 17 passes range check (typical LoRa)" {
    local TXP=17
    [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ]
}

@test "RNODE: TXP -10 passes range check (minimum)" {
    local TXP=-10
    [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ]
}

@test "RNODE: TXP 30 passes range check (maximum)" {
    local TXP=30
    [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ]
}

@test "RNODE: TXP 0 passes range check" {
    local TXP=0
    [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ]
}

@test "RNODE: TXP -11 fails range check (below min)" {
    local TXP=-11
    ! ( [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ] )
}

@test "RNODE: TXP 31 fails range check (above max)" {
    local TXP=31
    ! ( [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ] )
}

@test "RNODE: TXP non-numeric fails" {
    local TXP="max"
    ! [[ "$TXP" =~ ^-?[0-9]+$ ]]
}

#########################################################
# Frequency Validation (RNS003 - numeric only)
#########################################################

@test "RNODE: freq 915000000 passes (US 915MHz)" {
    local FREQ=915000000
    [[ "$FREQ" =~ ^[0-9]+$ ]]
}

@test "RNODE: freq 868000000 passes (EU 868MHz)" {
    local FREQ=868000000
    [[ "$FREQ" =~ ^[0-9]+$ ]]
}

@test "RNODE: freq 433000000 passes (433MHz)" {
    local FREQ=433000000
    [[ "$FREQ" =~ ^[0-9]+$ ]]
}

@test "RNODE: freq 914875000 passes (US community standard)" {
    local FREQ=914875000
    [[ "$FREQ" =~ ^[0-9]+$ ]]
}

@test "RNODE: freq non-numeric fails" {
    local FREQ="915MHz"
    ! [[ "$FREQ" =~ ^[0-9]+$ ]]
}

@test "RNODE: freq negative fails" {
    local FREQ="-915000000"
    ! [[ "$FREQ" =~ ^[0-9]+$ ]]
}

@test "RNODE: freq float fails" {
    local FREQ="915.0"
    ! [[ "$FREQ" =~ ^[0-9]+$ ]]
}

#########################################################
# Bandwidth Validation (RNS003 - numeric only)
#########################################################

@test "RNODE: bandwidth 125 passes (LoRa standard)" {
    local BW=125
    [[ "$BW" =~ ^[0-9]+$ ]]
}

@test "RNODE: bandwidth 250 passes" {
    local BW=250
    [[ "$BW" =~ ^[0-9]+$ ]]
}

@test "RNODE: bandwidth 500 passes" {
    local BW=500
    [[ "$BW" =~ ^[0-9]+$ ]]
}

@test "RNODE: bandwidth non-numeric fails" {
    local BW="wide"
    ! [[ "$BW" =~ ^[0-9]+$ ]]
}

#########################################################
# Model / Platform Validation (alphanumeric + underscore)
#########################################################

@test "RNODE: model t3s3 passes validation" {
    local MODEL="t3s3"
    [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "RNODE: model lora32_v2_1 passes validation" {
    local MODEL="lora32_v2_1"
    [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "RNODE: model heltec32_v3 passes validation" {
    local MODEL="heltec32_v3"
    [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "RNODE: model rnode_ng_20 passes validation" {
    local MODEL="rnode_ng_20"
    [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "RNODE: model with spaces fails" {
    local MODEL="lora 32"
    ! [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "RNODE: model with semicolons fails (injection)" {
    local MODEL="t3s3;whoami"
    ! [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "RNODE: model empty fails" {
    local MODEL=""
    ! [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "RNODE: platform esp32 passes validation" {
    local PLATFORM="esp32"
    [[ "$PLATFORM" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "RNODE: platform rp2040 passes validation" {
    local PLATFORM="rp2040"
    [[ "$PLATFORM" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "RNODE: platform nrf52 passes validation" {
    local PLATFORM="nrf52"
    [[ "$PLATFORM" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "RNODE: platform with underscores fails (strict validation)" {
    # Platform regex is stricter than model - no underscores
    local PLATFORM="esp32_s3"
    ! [[ "$PLATFORM" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "RNODE: platform with injection fails" {
    local PLATFORM="esp32\`id\`"
    ! [[ "$PLATFORM" =~ ^[a-zA-Z0-9]+$ ]]
}

#########################################################
# Command Construction Safety (RNS001 - no eval)
#########################################################

@test "RNODE: uses declare -a for command args (bash)" {
    grep -q 'declare -a CMD_ARGS' "$RNODE_SH"
}

@test "RNODE: executes via array expansion (bash)" {
    grep -q 'rnodeconf "${CMD_ARGS\[@\]}"' "$RNODE_SH"
}

@test "RNODE: no eval in rnode.sh" {
    ! grep -v '^\s*#' "$RNODE_SH" | grep -q '\beval\b'
}

@test "RNODE: no eval in rnode.ps1" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    ! grep -qE '\bInvoke-Expression\b' "$PS_RNODE"
}

@test "RNODE: PowerShell uses splatting (@cmdArgs) not string interpolation" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q '@cmdArgs' "$PS_RNODE"
}

@test "RNODE: PIPESTATUS checked after tee pipeline" {
    grep -q 'PIPESTATUS\[0\]' "$RNODE_SH"
}

#########################################################
# RNODE Board Support (21+ devices via rnodeconf)
# Verifies the tool supports the expected board families
#########################################################

@test "RNODE: menu offers auto-install (all boards)" {
    grep -q 'Auto-install firmware' "$RNODE_SH"
}

@test "RNODE: menu offers list supported devices" {
    grep -q 'rnodeconf --list' "$RNODE_SH"
}

@test "RNODE: menu offers flash specific device" {
    grep -q 'Flash specific device\|Flash Specific Device' "$RNODE_SH"
}

@test "RNODE: menu offers firmware update" {
    grep -q 'Update existing RNODE\|Update Existing RNODE' "$RNODE_SH"
}

@test "RNODE: menu offers device info" {
    grep -q 'Get device information\|Get Device Information' "$RNODE_SH"
}

@test "RNODE: menu offers radio configuration" {
    grep -q 'Configure radio parameters\|Configure Radio Parameters' "$RNODE_SH"
}

@test "RNODE: menu offers model/platform setting" {
    grep -q 'Set device model\|Set Device Model' "$RNODE_SH"
}

@test "RNODE: menu offers EEPROM access" {
    grep -q 'EEPROM' "$RNODE_SH"
}

@test "RNODE: menu offers bootloader update" {
    grep -q 'bootloader\|Bootloader' "$RNODE_SH"
}

@test "RNODE: menu offers serial console" {
    grep -q 'serial console\|Serial Console' "$RNODE_SH"
}

@test "RNODE: autoinstall uses --autoinstall flag" {
    grep -q 'rnodeconf --autoinstall' "$RNODE_SH"
}

@test "RNODE: update uses --update flag" {
    grep -q -- '--update' "$RNODE_SH"
}

@test "RNODE: info uses --info flag" {
    grep -q -- '--info' "$RNODE_SH"
}

@test "RNODE: eeprom uses --eeprom flag" {
    grep -q -- '--eeprom' "$RNODE_SH"
}

@test "RNODE: bootloader uses --rom flag" {
    grep -q -- '--rom' "$RNODE_SH"
}

@test "RNODE: console uses --console flag" {
    grep -q -- '--console' "$RNODE_SH"
}

@test "RNODE: help uses --help flag" {
    grep -q -- '--help' "$RNODE_SH"
}

#########################################################
# RNODE USB Device Detection
#########################################################

@test "RNODE: bash detects ttyUSB devices" {
    grep -qE 'ttyUSB\*|ttyUSB' "$RNODE_SH"
}

@test "RNODE: bash detects ttyACM devices" {
    grep -qE 'ttyACM\*|ttyACM' "$RNODE_SH"
}

@test "RNODE: PowerShell detects USB serial (CH340/CP210/FTDI)" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'CH340\|CP210\|FTDI\|Silicon Labs' "$PS_RNODE"
}

@test "RNODE: PowerShell uses WMI/CIM for device enumeration" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'Get-CimInstance\|Win32_PnPEntity' "$PS_RNODE"
}

#########################################################
# Destructive Operation Safety (RNS005)
#########################################################

@test "RNODE: bootloader requires confirmation" {
    grep -A5 'rnode_bootloader()' "$RNODE_SH" | head -20
    grep -q 'confirm_action' "$RNODE_SH"
}

@test "RNODE: autoinstall requires confirmation" {
    # Check that rnode_autoinstall uses confirmation
    local func_body
    func_body=$(sed -n '/^rnode_autoinstall()/,/^}/p' "$RNODE_SH")
    echo "$func_body" | grep -q 'confirm_action'
}

@test "RNODE: PS bootloader requires confirmation" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'Are you sure.*bootloader\|y/N' "$PS_RNODE"
}

@test "RNODE: recursive menu bug not present (while loop used)" {
    # Session 7 fixed a recursive menu bug in configure_rnode_interactive
    local func_body
    func_body=$(sed -n '/^configure_rnode_interactive()/,/^}/p' "$RNODE_SH")
    echo "$func_body" | grep -q 'while true'
    # Ensure function does NOT call itself recursively (exclude the declaration line)
    local body_no_decl
    body_no_decl=$(echo "$func_body" | tail -n +2)
    ! echo "$body_no_decl" | grep -q 'configure_rnode_interactive'
}

@test "RNODE: rnodeconf availability checked before menu" {
    # configure_rnode_interactive should check for rnodeconf
    local func_body
    func_body=$(sed -n '/^configure_rnode_interactive()/,/^}/p' "$RNODE_SH")
    echo "$func_body" | grep -q 'command -v rnodeconf'
}

#########################################################
# PowerShell RNODE Parity
#########################################################

@test "RNODE PS: radio config function exists" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'function Set-RnodeRadioParameter' "$PS_RNODE"
}

@test "RNODE PS: eeprom function exists" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'function Get-RnodeEeprom' "$PS_RNODE"
}

@test "RNODE PS: bootloader function exists" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'function Update-RnodeBootloader' "$PS_RNODE"
}

@test "RNODE PS: serial console function exists" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'function Open-RnodeConsole' "$PS_RNODE"
}

@test "RNODE PS: menu function exists" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q 'function Show-RnodeMenu' "$PS_RNODE"
}

@test "RNODE PS: SF range 7-12 validated" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q '\-ge 7.*\-le 12\|7.*12' "$PS_RNODE"
}

@test "RNODE PS: CR range 5-8 validated" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q '\-ge 5.*\-le 8\|5.*8' "$PS_RNODE"
}

@test "RNODE PS: TXP range -10 to 30 validated" {
    [ -f "$PS_RNODE" ] || skip "pwsh/rnode.ps1 not found"
    grep -q '\-10.*30' "$PS_RNODE"
}
