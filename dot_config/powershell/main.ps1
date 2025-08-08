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
$powershellAsync = Join-Path $powershellDir "/Async/"
$powershellModules = Join-Path $powershellDir "/Modules/"
$myFiles = @{
    completionHelper = Join-Path $powershellDir "bash_complete.sh"
    apiKeys          = Join-Path $powershellDir "api_keys.ps1"
    core             = Join-Path $powershellAsync "core.ps1"
}
$myAsync = [ordered]@{
    zoxide     = Join-Path $powershellAsync "zoxide.ps1"
    completion = Join-Path $powershellAsync "completion.ps1"
    alias      = Join-Path $powershellAsync "alias.ps1"
    chezmoi    = Join-Path $powershellAsync "chezmoi.ps1"
    psprofiler = Join-Path $powershellAsync "psprofiler.ps1"
    ohMyPosh   = Join-Path $powershellAsync "oh-my-posh.ps1"
    catppuccin = Join-Path $powershellAsync "catppuccin.ps1"
}

# Load Core
if (Test-Path $myFiles.core) {
    . $myFiles.core
}
else {
    Write-Error (Get-Color-String "<Red>Cant find core module of cutom profile")
}

# Add Modules to PS Module load list
if (Get-Os -eq "windows") {
    $env:PSModulePath += ";$powershellModules"
}
else {
    $env:PSModulePath += ":$powershellModules"
}

# Ensure all files exist
$myFilesAndModules = $myFiles + $myAsync
foreach ($key in $myFilesAndModules.Keys) {
    if (-Not (Test-Path $myFilesAndModules[$key])) {
        $global:ProfileIssues += @("Missing File: $key → $($myFilesAndModules[$key])")
    }
}

### Setup Temporary promt
function prompt {
    if ($global:Flavor) {
        "$($global:Flavor.Peach.Foreground())[Loading] $($global:Flavor.Text.Foreground())$($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) ";
    }
    else {
        "$([char]0x1b)[93m[Loading]$([char]0x1b)[0m $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) ";
    }
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
Start-AsyncModuleInitialization $myAsync 

# Print timing info
$time.Stop()

# Pretty print profile load result with timing
$elapsedMs = [math]::Round($time.Elapsed.TotalMilliseconds)
if ($elapsedMs -lt 250) {
    Write-Host (Get-Color-String "<Text>Profile loaded in <Green>$elapsedMs ms<Clear>")
}
elseif ($elapsedMs -lt 750) {
    Write-Host (Get-Color-String "<Text>Profile loaded in <Text>$elapsedMs ms<Clear>")
}
elseif ($elapsedMs -lt 2000) {
    Write-Host (Get-Color-String "<Text>Profile loaded in <Yellow>$elapsedMs ms<Clear>")
}
else {
    Write-Host (Get-Color-String "<Text>Profile loaded in <Red>$elapsedMs ms<Clear>")
}