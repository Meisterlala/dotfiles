### Oh My Posh init
$configPath = Resolve-Path (Join-Path $HOME ".config/oh-my-posh.yaml")
oh-my-posh init --config $configPath pwsh | Invoke-Expression