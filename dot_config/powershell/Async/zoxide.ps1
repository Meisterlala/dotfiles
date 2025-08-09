function Install-Zoxide {
    if ((Get-OperatingSystem) -eq "windows") {
        Write-Host (Get-ColorString "<Teal>Installing zoxide via winget…<Clear>")
        winget install --silent ajeetdsouza.zoxide
    }
    else {
        Write-Host (Get-ColorString "<Teal>Installing zoxide via curl…<Clear>")
        bash -c "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh"
    }
}


# Initialize zoxide
try {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
}
catch {
    if (-not (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        $global:ProfileIssues += "<Peach>zoxide is not installed. Call Install-Zoxide to install it.<Clear>"
    }
    else {
        $global:ProfileIssues += "<Peach>zoxide could not be initialized<Clear>"
    }
}
