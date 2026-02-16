#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for pwsh/backup.ps1 — Backup, restore, export, import
    Mirrors BATS integration_tests.bats for PowerShell parity
.NOTES
    Covers: RNS004 (path traversal prevention), archive validation, backup structure
    Uses .Contains() for literal string checks to avoid regex metacharacter issues.
    Uses -Match ONLY for [regex]::Matches() function counting.
#>

BeforeAll {
    # Read backup.ps1 source as text for static analysis
    $Script:BackupSource = Get-Content -Path "$PSScriptRoot/../pwsh/backup.ps1" -Raw
}

Describe "RNS004: Path Traversal Prevention in Import" {

    Context "Archive validation in Import-RnsConfiguration" {

        It "Source checks for '..' path traversal" {
            $Script:BackupSource.Contains("'\..'") | Should -BeTrue
        }

        It "Source checks for absolute paths starting with /" {
            $Script:BackupSource.Contains("StartsWith('/')") | Should -BeTrue
        }

        It "Source checks for absolute paths starting with \" {
            # Source has StartsWith('\') — one literal backslash in single quotes
            $Script:BackupSource.Contains("StartsWith('\')") | Should -BeTrue
        }

        It "Source logs security violations" {
            $Script:BackupSource.Contains("SECURITY: Rejected archive with invalid paths") | Should -BeTrue
        }

        It "Source uses ZipFile.OpenRead for validation" {
            $Script:BackupSource.Contains("ZipFile]::OpenRead") | Should -BeTrue
        }

        It "Source calls Dispose on zip handle" {
            $Script:BackupSource.Contains(".Dispose()") | Should -BeTrue
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
            $Script:BackupSource.Contains('.reticulum') | Should -BeTrue
        }

        It "Source checks for .nomadnetwork directory" {
            $Script:BackupSource.Contains('.nomadnetwork') | Should -BeTrue
        }

        It "Source checks for .lxmf directory" {
            $Script:BackupSource.Contains('.lxmf') | Should -BeTrue
        }

        It "Source validates expected content before extraction" {
            $Script:BackupSource.Contains('hasReticulumConfig') | Should -BeTrue
        }

        It "Source warns when archive lacks expected content" {
            $Script:BackupSource.Contains('does not appear to contain Reticulum') | Should -BeTrue
        }
    }
}

Describe "Import File Validation" {

    Context "File format checks" {

        It "Source validates .zip extension" {
            $Script:BackupSource.Contains("'\.zip$'") | Should -BeTrue
        }

        It "Source checks file existence with Test-Path" {
            $Script:BackupSource.Contains('Test-Path $importFile') | Should -BeTrue
        }

        It "Source requires confirmation before overwrite" {
            $Script:BackupSource.Contains('overwrite your current configuration') | Should -BeTrue
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
            $Script:BackupSource.Contains('function Export-RnsConfiguration') | Should -BeTrue
        }

        It "Export uses Compress-Archive" {
            $Script:BackupSource.Contains('Compress-Archive') | Should -BeTrue
        }

        It "Export uses timestamped filename" {
            $Script:BackupSource.Contains('yyyyMMdd_HHmmss') | Should -BeTrue
        }

        It "Export cleans up temp directory" {
            $Script:BackupSource.Contains('Remove-Item') -and $Script:BackupSource.Contains('tempExport') -and $Script:BackupSource.Contains('Recurse') | Should -BeTrue
        }

        It "Export logs the operation" {
            $Script:BackupSource.Contains('Write-RnsLog') -and $Script:BackupSource.Contains('Exported') | Should -BeTrue
        }
    }
}

Describe "Backup Management" {

    Context "New-Backup function" {

        It "New-Backup function exists" {
            $Script:BackupSource.Contains('function New-Backup') | Should -BeTrue
        }

        It "New-Backup uses SupportsShouldProcess" {
            # Function declaration and [CmdletBinding] are on separate lines
            $fnIdx = $Script:BackupSource.IndexOf('function New-Backup')
            $fnIdx | Should -BeGreaterOrEqual 0
            $cbIdx = $Script:BackupSource.IndexOf('[CmdletBinding(SupportsShouldProcess)]', $fnIdx)
            $cbIdx | Should -BeGreaterThan $fnIdx
            ($cbIdx - $fnIdx) | Should -BeLessThan 100
        }

        It "New-Backup creates backup directory" {
            $Script:BackupSource.Contains('New-Item') -and $Script:BackupSource.Contains('Directory') -and $Script:BackupSource.Contains('BackupDir') | Should -BeTrue
        }

        It "New-Backup backs up .reticulum directory" {
            $Script:BackupSource.Contains('Copy-Item') -and $Script:BackupSource.Contains('reticulumDir') | Should -BeTrue
        }
    }

    Context "Restore-Backup function" {

        It "Restore-Backup function exists" {
            $Script:BackupSource.Contains('function Restore-Backup') | Should -BeTrue
        }

        It "Restore requires confirmation" {
            $Script:BackupSource.Contains('overwrite your current configuration') | Should -BeTrue
        }

        It "Restore lists available backups" {
            $Script:BackupSource.Contains('Available backups') | Should -BeTrue
        }
    }

    Context "Remove-OldBackups function" {

        It "Remove-OldBackups function exists" {
            $Script:BackupSource.Contains('function Remove-OldBackups') | Should -BeTrue
        }

        It "Keeps 3 most recent backups" {
            $Script:BackupSource.Contains('-le 3') | Should -BeTrue
        }

        It "Requires confirmation before deletion" {
            $Script:BackupSource.Contains('Delete') -and $Script:BackupSource.Contains('old backup') | Should -BeTrue
        }

        It "Logs deletion" {
            $Script:BackupSource.Contains('Write-RnsLog') -and $Script:BackupSource.Contains('Deleted') -and $Script:BackupSource.Contains('backup') | Should -BeTrue
        }
    }

    Context "Get-AllBackups function" {

        It "Get-AllBackups function exists" {
            $Script:BackupSource.Contains('function Get-AllBackups') | Should -BeTrue
        }

        It "Displays formatted dates" {
            $Script:BackupSource.Contains('formattedDate') | Should -BeTrue
        }

        It "Shows backup sizes" {
            $Script:BackupSource.Contains('backupSize') | Should -BeTrue
        }
    }
}

Describe "Backup Menu Structure" {

    It "Show-BackupMenu function exists" {
        $Script:BackupSource.Contains('function Show-BackupMenu') | Should -BeTrue
    }

    It "Menu uses while loop (not recursive)" {
        $Script:BackupSource.Contains('while ($true)') | Should -BeTrue
    }

    It "Menu has back option (0)" {
        $Script:BackupSource.Contains('"0"') -and $Script:BackupSource.Contains('return') | Should -BeTrue
    }

    It "Menu shows backup count" {
        $Script:BackupSource.Contains('backupCount') | Should -BeTrue
    }

    It "Menu has all 6 options" {
        $Script:BackupSource.Contains('"1"') -and $Script:BackupSource.Contains('New-Backup') | Should -BeTrue
        $Script:BackupSource.Contains('"2"') -and $Script:BackupSource.Contains('Restore-Backup') | Should -BeTrue
        $Script:BackupSource.Contains('"3"') -and $Script:BackupSource.Contains('Get-AllBackups') | Should -BeTrue
        $Script:BackupSource.Contains('"4"') -and $Script:BackupSource.Contains('Remove-OldBackups') | Should -BeTrue
        $Script:BackupSource.Contains('"5"') -and $Script:BackupSource.Contains('Export-RnsConfiguration') | Should -BeTrue
        $Script:BackupSource.Contains('"6"') -and $Script:BackupSource.Contains('Import-RnsConfiguration') | Should -BeTrue
    }
}

Describe "Function Count" {

    It "backup.ps1 has exactly 7 functions" {
        $functionCount = ([regex]::Matches($Script:BackupSource, '^\s*function\s+', [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
        $functionCount | Should -Be 7
    }
}
