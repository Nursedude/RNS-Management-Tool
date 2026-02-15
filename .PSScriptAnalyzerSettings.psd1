@{
    # PSScriptAnalyzer settings for RNS Management Tool
    # This is a Terminal UI (TUI) application — Write-Host is intentional
    # for interactive colored console output (menus, status, box-drawing).

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseBOMForUnicodeEncodedFile'
    )
}
