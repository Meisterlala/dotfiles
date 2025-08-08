# Chezmoi helpers module

if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (chezmoi completion powershell | Out-String) })
    function Edit-Chezmoi {
        param([string]$FilePath)
        if ([string]::IsNullOrWhiteSpace($FilePath)) { chezmoi managed -t }
        else { chezmoi edit --watch -a $FilePath }
    }
    Set-Alias -Name ce -Value Edit-Chezmoi | Out-Null
}
else {
    if (Get-Command Add-ProfileIssue -ErrorAction SilentlyContinue) {
        Add-ProfileIssue 'chezmoi' 'not installed'
    }
}


