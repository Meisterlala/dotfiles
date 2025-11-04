function Install-Carapace
{
    If ($global:os -eq "windows")
    {
        Install-WithWinget "rsteube.Carapace"

    } else
    {
        Install-WithYayPacman "carapace-bin"
    }
}

function Enable-Carapace
{

    try
    {
        $env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
        Set-PSReadLineOption -Colors @{ "Selection" = "`e[7m" }
        Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
        carapace _carapace | Out-String | Invoke-Expression
    } catch
    {
        if (-not (Find-Command carapace -ErrorAction SilentlyContinue))
        {
            $Global:ProfileHints += "<Teal>carapace<Clear> not found. Install with <Mauve>Install-Carapace"
            return
        }
    }
}

# Load Carapace
Enable-Carapace
