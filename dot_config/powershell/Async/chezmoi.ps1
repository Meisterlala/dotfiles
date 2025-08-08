
### Setup Chezmoi
if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (chezmoi completion powershell | Out-String) })

    function Edit-Chezmoi {
        param (
            [string]$FilePath
        )
        # List all if empty
        if ([string]::IsNullOrWhiteSpace($FilePath)) {
            chezmoi managed -t
        }
        else {
            chezmoi edit --watch -a $FilePath
        }
    }
    Set-Alias -Name ce -Value Edit-Chezmoi | Out-Null
}


