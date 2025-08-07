# Zoxide initialization module

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
}
else {
    if (Get-Command Add-ProfileIssue -ErrorAction SilentlyContinue) {
        Add-ProfileIssue 'zoxide' 'not installed'
    }
}


