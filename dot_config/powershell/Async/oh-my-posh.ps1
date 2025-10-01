### Oh My Posh init
$configPath = Resolve-Path (Join-Path $HOME ".config/oh-my-posh.yaml")
oh-my-posh init --config $configPath pwsh | Invoke-Expression

# re-add zoxide if needed
$global:__zoxide_hooked = (Get-Variable __zoxide_hooked -ErrorAction Ignore -ValueOnly)
if ($global:__zoxide_hooked -eq 1) {
    $global:__zoxide_prompt_old = $function:prompt

    function global:prompt {
        if ($null -ne $__zoxide_prompt_old) {
            & $__zoxide_prompt_old
        }
        $null = __zoxide_hook
    }
}

# Re-render the prompt as soon as possible
try {
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}
catch {
    # PSReadLine not available; ignore
}
