$time = [System.Diagnostics.Stopwatch]::StartNew()

# Disable update check
if ($env:POWERSHELL_UPDATECHECK -ne 'LTS')
{
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'LTS', 'User')
}

# Global vars
$global:ProfileIssues = @()
$global:ProfileHints = @()
$global:ProfileLoadedAsync = @()


# Related Files
$powershellDir = Join-Path $HOME ".config/powershell/"
$powershellAsync = Join-Path $powershellDir "/Async/"
$powershellModules = Join-Path $powershellDir "/Modules/"
$global:myFiles = @{
    completionHelper = Join-Path $powershellDir "bash_complete.sh"
    apiKeys          = Join-Path $powershellDir "api_keys.ps1"
    core             = Join-Path $powershellDir "core.ps1"
    env              = Join-Path $powershellDir "env.ps1"
}
$global:myAsync = [ordered]@{
    zoxide     = Join-Path $powershellAsync "zoxide.ps1"
    completion = Join-Path $powershellAsync "completion.ps1"
    alias      = Join-Path $powershellAsync "alias.ps1"
    chezmoi    = Join-Path $powershellAsync "chezmoi.ps1"
    psprofiler = Join-Path $powershellAsync "psprofiler.ps1"
    ohMyPosh   = Join-Path $powershellAsync "oh-my-posh.ps1"
    catppuccin = Join-Path $powershellAsync "catppuccin.ps1"
}

# Load Core
if (Test-Path $global:myFiles.core)
{
    . $global:myFiles.core
} else
{
    Write-Error "Cant find core module of custom profile (main.ps1)"
    return
}

# Load apiKeys
if (Test-Path $global:myFiles.apiKeys)
{
    . $global:myFiles.apiKeys
}
# Load Env variables
if (Test-Path $global:myFiles.env)
{
    . $global:myFiles.env
}

# Add Modules to PS Module load list
if ((Get-OperatingSystem) -eq "windows")
{
    $env:PSModulePath += "; $powershellModules"
} else
{
    $env:PSModulePath += ":$powershellModules"
}

# Ensure all files exist
$myFilesAndModules = $myFiles + $myAsync
foreach ($key in $myFilesAndModules.Keys)
{
    if (-Not (Test-Path $myFilesAndModules[$key]))
    {
        $global:ProfileIssues += @("Missing File: $key → $($myFilesAndModules[$key])")
    }
}

### Setup Temporary promt
function prompt
{
    return "$([char]0x1b)[38;2;239;159;118m[Loading]$([char]0x1b)[0m $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
}

### Setup-PSReadline
# Show multi line history (Toggle with F2)
Set-PSReadLineOption -PredictionViewStyle ListView
# Show multi line autocomplete
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
# Match with already written command
# Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
# Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Alt+e -Function ViEditVisually

# Load last Profile hints
$lastProfileHints = (Get-LastProfileHints).hints

Import-Module ProfileAsync
# Load with AsyncProfile
$AsyncScriptblock = {
    . $global:myAsync.catppuccin
    . $global:myAsync.ohMyPosh
    . $global:myAsync.zoxide
    . $global:myAsync.completion
    . $global:myAsync.alias
    . $global:myAsync.chezmoi
    . $global:myAsync.psprofiler

    Save-ProfileHints
}

Import-ProfileAsync $AsyncScriptblock -Delay 200

# Print timing info
$time.Stop()

# Show any hints from the last session
if ($lastProfileHints.Count -gt 0)
{
    $hintName = if ($lastProfileHints.Count -eq 1)
    { "Hint" 
    } else
    { "Hints" 
    }
    Write-Host "$([char]0x1b)[38;2;238;190;190m$($lastProfileHints.Count) $hintName $([char]0x1b)[0mavalible with $([char]0x1b)[38;2;202;158;230mShow-ProfileHints$([char]0x1b)[0m, " -NoNewline
} 

# Pretty print profile load result with timing
$elapsedMs = [math]::Round($time.Elapsed.TotalMilliseconds)
if ($elapsedMs -lt 250)
{
    Write-Host "Profile loaded in $([char]0x1b)[92m$elapsedMs ms$([char]0x1b)[0m"
} elseif ($elapsedMs -lt 750)
{
    Write-Host "Profile loaded in $([char]0x1b)[39m$elapsedMs ms$([char]0x1b)[0m"
} elseif ($elapsedMs -lt 2000)
{
    Write-Host "Profile loaded in $([char]0x1b)[93m$elapsedMs ms$([char]0x1b)[0m"
} else
{
    Write-Host "Profile loaded in $([char]0x1b)[91m$elapsedMs ms$([char]0x1b)[0m"
}
