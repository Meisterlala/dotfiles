# Linux Powershell

$env:PATH = "$HOME/.local/bin:$env:PATH"


# Load Main Data
. (Join-Path $HOME ".config/powershell/main.ps1")
