function Enable-Direnv()
{
    try
    {
        Invoke-Expression "$(direnv hook pwsh)"
    } catch
    {
        $Global:ProfileHints += "<Teal>direnv<Clear> not found. Install with <Mauve>Install-Carapace"
    }
}

function Install-Direnv
{
    If ($global:os -eq "windows")
    {
        Install-WithWinget "direnv.direnv"
    } else
    {
        Install-WithYayPacman "direnv"
    }
}
