# Prompt and Oh My Posh integration (optional)

function Initialize-PromptTheme {
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        oh-my-posh init --config "$HOME/.config/oh-my-posh.yaml" pwsh | Invoke-Expression
    }
}

Export-ModuleMember -Function Initialize-PromptTheme

