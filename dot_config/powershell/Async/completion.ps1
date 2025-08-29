function Install-Carapace {
    If ($global:os -eq "windows") {

    } else {
        Install-WithYayPacman "carapace-bin"
    }
}

function Initilize-Carapace {
    if (-not (Get-Command carapace -ErrorAction SilentlyContinue)) {
        $Global:ProfileHints += "<Teal>carapace<Clear> not found. Install with <Mauve>Install-Carapace"
        return
    }

    $env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
    Set-PSReadLineOption -Colors @{ "Selection" = "`e[7m" }
    Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
    carapace _carapace | Out-String | Invoke-Expression
}

# Load Carapace
Initilize-Carapace
