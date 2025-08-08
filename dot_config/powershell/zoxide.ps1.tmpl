# Install zoxide if not present
if (-not (Get-Command zoxide -ErrorAction SilentlyContinue))
{
    {{ if eq .chezmoi.os "windows" -}}
    Write-Host "Installing zoxide via winget…" -ForegroundColor Cyan
    winget install --silent ajeetdsouza.zoxide
    {{- else -}}
    Write-Host "Installing zoxide via curl…" -ForegroundColor Cyan
    bash -c "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh"
    {{- end }}
}

# Initialize zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue)
{
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
}
