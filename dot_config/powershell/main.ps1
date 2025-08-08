# Disable update check
if ($env:POWERSHELL_UPDATECHECK -ne 'LTS')
{
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'LTS', 'User')
}

$time = [System.Diagnostics.Stopwatch]::StartNew()
$global:ProfileIssues = @()

# Related Files
$powershellDir = Join-Path $HOME ".config/powershell/"
$powershellModules = Join-Path $powershellDir "/modules/"
$files = @{
    completionHelper = Join-Path $powershellDir "bash_complete.sh"
    apiKeys = Join-Path $powershellDir "api_keys.ps1"

    core = Join-Path $powershellModules "core.ps1"
    zoxide = Join-Path $powershellModules "zoxide.ps1"
    completion = Join-Path $powershellModules "completion.ps1"
    alias = Join-Path $powershellModules "alias.ps1"
    chezmoi = Join-Path $powershellModules "chezmoi.ps1"
    psprofiler = Join-Path $powershellModules "psprofiler.ps1"
}

# Ensure all files exist
foreach ($key in $files.Keys) {
    if (-Not (Test-Path $files[$key])) {
        $global:ProfileIssues += @("Missing File: $key → $($files[$key])")
    }
}

# Load Core
. $files.core

### Setup-PSReadline
# Show multi line history (Toggle with F2)
Set-PSReadLineOption -PredictionViewStyle ListView
# Show multi line autocomplete
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
# Match with already written command
# Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
# Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward


### Oh My Posh init
oh-my-posh init --config "$HOME/.config/oh-my-posh.yaml" pwsh | Invoke-Expression

Import-File $files.apiKeys
Import-File $files.zoxide
Import-File $files.completion
Import-File $files.alias
Import-File $files.chezmoi
Import-File $files.psprofiler


# Print timing info
$time.Stop()

foreach ($issue in $global:ProfileIssues) {
    Write-Warning $issue
}


Write-Host "Profile loaded successfully in $([math]::Round($time.Elapsed.TotalMilliseconds))ms"
