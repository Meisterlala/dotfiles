# Linux Powershell

$env:PATH = "$HOME/.local/bin:$env:PATH"
$env:CILIUM_NAMESPACE = "cilium"

# Load Main Data
. (Join-Path $HOME ".config/powershell/main.ps1")
