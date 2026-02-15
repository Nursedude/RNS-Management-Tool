#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/backup.ps1 — Backup, restore, export, import
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: RNS004 (path traversal prevention), archive validation, backup structure
#>

BeforeAll {
    # Read backup.ps1 source as text for static analysis
    $Script:BackupSource = Get-Content -Path "$PSScriptRoot/../pwsh/backup.ps1" -Raw
}

Describe "RNS004: Path Traversal Prevention in Import" {

    Context "Archive validation in Import-RnsConfiguration" {

        It "Source checks for '..' path traversal" {
            $Script:BackupSource | Should -Match '\.\.'
        }

        It "Source checks for absolute paths starting with /" {
            $Script:BackupSource | Should -Match "StartsWith\('/'\)"
        }

        It "Source checks for absolute paths starting with \\" {
            $Script:BackupSource | Should -Match "StartsWith\('\\\\'\)"
        }

        It "Source logs security violations" {
            $Script:BackupSource | Should -Match 'SECURITY.*Rejected archive'
        }

        It "Source uses ZipFile.OpenRead for validation" {
            $Script:BackupSource | Should -Match 'ZipFile.*OpenRead'
        }

        It "Source calls Dispose on zip handle" {
            $Script:BackupSource | Should -Match '\.Dispose\(\)'
        }

        It "Source validates before extraction" {
            # Validation block must appear before Expand-Archive
            $validationIdx = $Script:BackupSource.IndexOf('ZipFile')
            $expandIdx = $Script:BackupSource.IndexOf('Expand-Archive')
            $validationIdx | Should -BeLessThan $expandIdx
        }
    }

    Context "Traversal pattern matching" {

        It "Detects simple parent traversal '../'" {
            "../etc/passwd" -match '\.\.' | Should -BeTrue
        }

        It "Detects nested traversal '../../'" {
            "../../etc/shadow" -match '\.\.' | Should -BeTrue
        }

        It "Detects traversal in middle of path" {
            ".reticulum/../../../etc/passwd" -match '\.\.' | Should -BeTrue
        }

        It "Clean path does not trigger traversal check" {
            ".reticulum/config" -match '\.\.' | Should -BeFalse
        }

        It "Detects absolute path starting with /" {
            "/etc/passwd".StartsWith('/') | Should -BeTrue
        }

        It "Detects absolute path starting with \\" {
            "\Windows\System32".StartsWith('\') | Should -BeTrue
        }

        It "Relative path does not trigger absolute check" {
            ".reticulum/config".StartsWith('/') | Should -BeFalse
            ".reticulum/config".StartsWith('\') | Should -BeFalse
        }
    }
}

Describe "Archive Content Validation" {

    Context "Expected config directory detection" {

        It "Source checks for .reticulum directory" {
            $Script:BackupSource | Should -Match '\.reticulum'
        }

        It "Source checks for .nomadnetwork directory" {
            $Script:BackupSource | Should -Match '\.nomadnetwork'
        }

        It "Source checks for .lxmf directory" {
            $Script:BackupSource | Should -Match '\.lxmf'
        }

        It "Source validates expected content before extraction" {
            $Script:BackupSource | Should -Match 'hasReticulumConfig'
        }

        It "Source warns when archive lacks expected content" {
            $Script:BackupSource | Should -Match 'does not appear to contain Reticulum'
        }
    }
}

Describe "Import File Validation" {

    Context "File format checks" {

        It "Source validates .zip extension" {
            $Script:BackupSource | Should -Match "\.zip\$"
        }

        It "Source checks file existence with Test-Path" {
            $Script:BackupSource | Should -Match 'Test-Path \$importFile'
        }

        It "Source requires confirmation before overwrite" {
            $Script:BackupSource | Should -Match 'overwrite your current configuration'
        }

        It "Source creates backup before import" {
            # New-Backup is called before Expand-Archive
            $backupIdx = $Script:BackupSource.IndexOf('New-Backup')
            $expandIdx = $Script:BackupSource.IndexOf('Expand-Archive')
            $backupIdx | Should -BeGreaterThan 0
            $expandIdx | Should -BeGreaterThan $backupIdx
        }
    }
}

Describe "Export Functionality" {

    Context "Export-RnsConfiguration" {

        It "Export function exists" {
            $Script:BackupSource | Should -Match 'function Export-RnsConfiguration'
        }

        It "Export uses Compress-Archive" {
            $Script:BackupSource | Should -Match 'Compress-Archive'
        }

        It "Export uses timestamped filename" {
            $Script:BackupSource | Should -Match 'yyyyMMdd_HHmmss'
        }

        It "Export cleans up temp directory" {
            $Script:BackupSource | Should -Match 'Remove-Item.*tempExport.*Recurse'
        }

        It "Export logs the operation" {
            $Script:BackupSource | Should -Match 'Write-RnsLog.*Exported'
        }
    }
}

Describe "Backup Management" {

    Context "New-Backup function" {

        It "New-Backup function exists" {
            $Script:BackupSource | Should -Match 'function New-Backup'
        }

        It "New-Backup uses SupportsShouldProcess" {
            $Script:BackupSource | Should -Match 'New-Backup.*\[CmdletBinding\(SupportsShouldProcess\)\]' -Because "destructive operation should support -WhatIf"
        }

        It "New-Backup creates backup directory" {
            $Script:BackupSource | Should -Match 'New-Item.*Directory.*BackupDir'
        }

        It "New-Backup backs up .reticulum directory" {
            $Script:BackupSource | Should -Match 'Copy-Item.*reticulumDir'
        }
    }

    Context "Restore-Backup function" {

        It "Restore-Backup function exists" {
            $Script:BackupSource | Should -Match 'function Restore-Backup'
        }

        It "Restore requires confirmation" {
            $Script:BackupSource | Should -Match 'overwrite your current configuration'
        }

        It "Restore lists available backups" {
            $Script:BackupSource | Should -Match 'Available backups'
        }
    }

    Context "Remove-OldBackups function" {

        It "Remove-OldBackups function exists" {
            $Script:BackupSource | Should -Match 'function Remove-OldBackups'
        }

        It "Keeps 3 most recent backups" {
            $Script:BackupSource | Should -Match '-le 3'
        }

        It "Requires confirmation before deletion" {
            $Script:BackupSource | Should -Match 'Delete.*old backup'
        }

        It "Logs deletion" {
            $Script:BackupSource | Should -Match 'Write-RnsLog.*Deleted.*backup'
        }
    }

    Context "Get-AllBackups function" {

        It "Get-AllBackups function exists" {
            $Script:BackupSource | Should -Match 'function Get-AllBackups'
        }

        It "Displays formatted dates" {
            $Script:BackupSource | Should -Match 'formattedDate'
        }

        It "Shows backup sizes" {
            $Script:BackupSource | Should -Match 'backupSize'
        }
    }
}

Describe "Backup Menu Structure" {

    It "Show-BackupMenu function exists" {
        $Script:BackupSource | Should -Match 'function Show-BackupMenu'
    }

    It "Menu uses while loop (not recursive)" {
        $Script:BackupSource | Should -Match 'while\s*\(\$true\)'
    }

    It "Menu has back option (0)" {
        $Script:BackupSource | Should -Match '"0".*return'
    }

    It "Menu shows backup count" {
        $Script:BackupSource | Should -Match 'backupCount'
    }

    It "Menu has all 6 options" {
        $Script:BackupSource | Should -Match '"1".*New-Backup'
        $Script:BackupSource | Should -Match '"2".*Restore-Backup'
        $Script:BackupSource | Should -Match '"3".*Get-AllBackups'
        $Script:BackupSource | Should -Match '"4".*Remove-OldBackups'
        $Script:BackupSource | Should -Match '"5".*Export-RnsConfiguration'
        $Script:BackupSource | Should -Match '"6".*Import-RnsConfiguration'
    }
}

Describe "Function Count" {

    It "backup.ps1 has exactly 7 functions" {
        $functionCount = ([regex]::Matches($Script:BackupSource, '^\s*function\s+', [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
        $functionCount | Should -Be 7
    }
}
