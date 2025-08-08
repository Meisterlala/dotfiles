function Install-Zoxide {
    if (Get-OS -eq "windows") {
        Write-Host "Installing zoxide via winget…" -ForegroundColor Cyan
        winget install --silent ajeetdsouza.zoxide
    }
    else {
        Write-Host "Installing zoxide via curl…" -ForegroundColor Cyan
        bash -c "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh"
    }
}


# Initialize zoxide
try {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
}
catch {
    if (-not (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        $global:ProfileIssues += "zoxide is not installed. Call Install-Zoxide to install it."
    }
    else {
        $global:ProfileIssues += "zoxide could not be initialized"
    }
}
