# Disable update check
if ($env:POWERSHELL_UPDATECHECK -ne 'LTS') {
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'LTS', 'User')
}

$time = [System.Diagnostics.Stopwatch]::StartNew()
# Global vars
$global:ProfileIssues = @()
$global:ProfileLoadedAsync = @()


# Related Files
$powershellDir = Join-Path $HOME ".config/powershell/"
$powershellModules = Join-Path $powershellDir "/modules/"
$myFiles = @{
    completionHelper = Join-Path $powershellDir "bash_complete.sh"
    apiKeys          = Join-Path $powershellDir "api_keys.ps1"
    core             = Join-Path $powershellModules "core.ps1"
}
$myModules = [ordered]@{
    zoxide     = Join-Path $powershellModules "zoxide.ps1"
    completion = Join-Path $powershellModules "completion.ps1"
    alias      = Join-Path $powershellModules "alias.ps1"
    chezmoi    = Join-Path $powershellModules "chezmoi.ps1"
    psprofiler = Join-Path $powershellModules "psprofiler.ps1"
    ohMyPosh   = Join-Path $powershellModules "oh-my-posh.ps1"
}

# Load Core
if (Test-Path $myFiles.core) {
    . $myFiles.core
}
else {
    Write-Error "Cant find core module of cutom profile"
}

# Ensure all files exist
$myFilesAndModules = $myFiles + $myModules
foreach ($key in $myFilesAndModules.Keys) {
    if (-Not (Test-Path $myFilesAndModules[$key])) {
        $global:ProfileIssues += @("Missing File: $key → $($myFilesAndModules[$key])")
    }
}

### Setup Temporary promt
function prompt {
    # We will override this prompt, however because it is loading async we want to communicate that the real prompt is still loading.
    "$([char]0x1b)[93m[Loading]$([char]0x1b)[0m $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) ";
}

### Setup-PSReadline
# Show multi line history (Toggle with F2)
Set-PSReadLineOption -PredictionViewStyle ListView
# Show multi line autocomplete
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
# Match with already written command
# Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
# Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward


# Defer module/script loading asynchronously during idle
Start-AsyncModuleInitialization $myModules 

# Print timing info
$time.Stop()

# Pretty print profile load result with timing
$elapsedMs = [math]::Round($time.Elapsed.TotalMilliseconds)
Write-Host "Profile loaded in " -NoNewline
if ($elapsedMs -lt 250) {
    Write-Host "$elapsedMs ms" -ForegroundColor Green
}
elseif ($elapsedMs -lt 750) {
    Write-Host "$elapsedMs ms"
}
elseif ($elapsedMs -lt 2000) {
    Write-Host "$elapsedMs ms" -ForegroundColor Yellow
}
else {
    Write-Host "$elapsedMs ms" -ForegroundColor Red
}