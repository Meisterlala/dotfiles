# Core functions
function Get-OperatingSystem {
    if ($env:OS -eq "Windows_NT") {
        return "windows"
    }
    else {
        return "linux"
    }
}

function Show-ProfileIssues {
    # Render all errors
    foreach ($issue in $global:ProfileIssues) {
        Write-Warning (Get-ColorString $issue)
    }
}

function Show-ProfileHints {
    # Render all errors
    foreach ($issue in $global:ProfileHints) {
        Write-Host (Get-ColorString $issue)
    }
}

function Show-ProfileAsync {
    # Render all errors
    foreach ($issue in $global:ProfileLoadedAsync) {
        Write-Host (Get-ColorString $issue)
    }
}

function Save-ProfileHints {
    try {
        $configDir = Join-Path $HOME ".config/powershell"
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        $filePath = Join-Path $configDir "last_hints"
        $payload = @{ hints = @($global:ProfileHints) }
        $json = $payload | ConvertTo-Json -Depth 5
        Set-Content -Path $filePath -Value $json -Encoding utf8
        return $payload
    }
    catch {
        $global:ProfileIssues += "Failed to save profile hints: $($_.Exception.Message)"
    }
}

function Get-LastProfileHints {
    try {
        $filePath = Join-Path $HOME ".config/powershell/last_hints"
        if (-not (Test-Path $filePath)) {
            return @{ hints = @() }
        }

        $raw = Get-Content -Path $filePath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj) {
            return @{ hints = @() }
        }
        return $obj
    }
    catch {
        $global:ProfileIssues += "Failed to load last profile hints: $($_.Exception.Message)"
        return @{ hints = @() }
    }
}

function Install-WithWinget {
    param (
        [Parameter(Mandatory)]
        [string] $name
    )
    if (Get-OperatingSystem -ne "windows") {
        Write-Warning "You can use winget on windows"
    }

    try {
        winget install --exact $name --accept-package-agreements 
    }
    catch {
        throw "Could not install $name with winget: $_"
    }
}

function Install-WithYayPacman {
    param (
        [Parameter(Mandatory, ValueFromRemainingArguments = $true)]
        [string[]] $Name
    )

    if (Get-OperatingSystem -ne "linux") {
        Write-Warning "You can use yay/pacman on linux"
        return
    }

    $useYay = $false
    if (Get-Command -Name 'yay' -ErrorAction SilentlyContinue) {
        $useYay = $true
    }
    elseif (-not (Get-Command -Name 'pacman' -ErrorAction SilentlyContinue)) {
        throw "Neither 'yay' nor 'pacman' is available on PATH."
    }

    try {
        $packageArgs = @('-S', '--needed', '--noconfirm') + $Name
        if ($useYay) {
            & yay @packageArgs
        }
        else {
            & sudo pacman @packageArgs
        }
    }
    catch {
        throw "Could not install $([string]::Join(', ', $Name)) with $([bool]$useYay ? 'yay' : 'pacman'): $_"
    }
}


function install-withapt {
    param (
        [Parameter(Mandatory, ValueFromRemainingArguments = $true)]
        [string[]] $Name
    )

    if (Get-OperatingSystem -ne "linux") {
        Write-Warning "You can use apt on linux"
        return
    }

    $aptGetCmd = Get-Command -Name 'apt-get' -ErrorAction SilentlyContinue
    $aptCmd = Get-Command -Name 'apt' -ErrorAction SilentlyContinue
    if (-not $aptGetCmd -and -not $aptCmd) {
        throw "Neither 'apt-get' nor 'apt' is available on PATH."
    }

    try {
        $packageArgs = @('install', '-y') + $Name
        if ($aptGetCmd) {
            & sudo apt-get @packageArgs
        }
        else {
            & sudo apt @packageArgs
        }
    }
    catch {
        throw "Could not install $([string]::Join(', ', $Name)) with apt: $_"
    }
}

function Get-ColorString {
    param (
        [Parameter(Mandatory)]
        [string] $in
    )
    $handler = Get-Command -Name 'Get-ColorStringCatppuccin' -CommandType Function -ErrorAction SilentlyContinue
    if ($null -ne $handler) {
        return (Get-ColorStringCatppuccin -in $in)
    }

    # Fallback: strip tags if handler isn't loaded yet
    return [regex]::Replace($in, '<([A-Za-z0-9]+)>', '')
}


# Schedules module/script loading to occur asynchronously during idle time.
# Each queued script is executed one-at-a-time on each idle event, which keeps
# the initial prompt responsive.
function Start-AsyncModuleInitialization {
    param(
        [Parameter(Mandatory)]
        [hashtable] $myModules
    )
    # Avoid double registration if called more than once
    if (Get-Variable -Name '__initQueue' -Scope Global -ErrorAction SilentlyContinue) {
        return
    }

    $global:__initQueue = New-Object System.Collections.Queue
    foreach ($file in $myModules.Keys) { 
        [void]$global:__initQueue.Enqueue(@{
                Name = $file
                Path = $myModules[$file]
            }) 
    }

    # Register idle handler; hidden from Get-EventSubscriber with -SupportEvent
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -SupportEvent -Action {
        try {
            if ($global:__initQueue.Count -gt 0) {
                $file = $global:__initQueue.Dequeue()
                $moduleTime = [System.Diagnostics.Stopwatch]::StartNew()

                try {
                    # Create Module and load it
                    New-Module -Name $file.Name -ScriptBlock { 
                        . $args[0]
                    } -ArgumentList $file.Path | Import-Module -Global -DisableNameChecking
                    
                    # Track it
                    $elapesdmoduleMS = [math]::Round($moduleTime.Elapsed.TotalMilliseconds)
                    $global:ProfileLoadedAsync += "<Teal>$($file.Name) <Rosewater>($elapesdmoduleMS ms)<Clear> from $($file.Path)"
                }
                catch {
                    $moduleTime.Stop() 
                    $global:ProfileIssues += "Async init failed <Teal>(${$file.Name})<Clear>: $($_.Exception.Message)"
                    return
                }
            }
            else {
                # Finished: unregister and cleanup
                Unregister-Event -SubscriptionId $EventSubscriber.SubscriptionId -Force

                # Re-render the prompt as soon as possible
                try {
                    # [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                }
                catch {
                    # PSReadLine not available; ignore
                }

                # Display all errors
                Show-ProfileIssues
            }
        }
        catch {
            # Record and continue
            $global:ProfileIssues += "Async init handler error: $($_.Exception.Message)"
        }
    } | Out-Null
}