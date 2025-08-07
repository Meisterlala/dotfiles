# Core profile utilities and baseline configuration

if (-not $global:ProfileIssues) { $global:ProfileIssues = @() }

function Add-ProfileIssue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Message
    )
    $global:ProfileIssues += "${Name}: ${Message}"
}

# PSReadLine settings
try {
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}
catch {}

Export-ModuleMember -Function Add-ProfileIssue


