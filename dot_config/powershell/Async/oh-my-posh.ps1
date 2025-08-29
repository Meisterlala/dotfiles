### Oh My Posh init
$configPath = Resolve-Path (Join-Path $HOME ".config/oh-my-posh.yaml")
oh-my-posh init --config $configPath pwsh | Invoke-Expression


# Re-render the prompt as soon as possible
try {
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}
catch {
    # PSReadLine not available; ignore
}
