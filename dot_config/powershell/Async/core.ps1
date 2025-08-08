# Core functions
function Get-OS {
    if ($env:OS -eq "Windows_NT") {
        return "windows"
    }
    else {
        return "linux"
    }
}

function Get-Profile-Issues {
    # Render all errors
    foreach ($issue in $global:ProfileIssues) {
        Write-Warning (Get-Color-String $issue)
    }
}

function Get-Profile-Async {
    # Render all errors
    foreach ($issue in $global:ProfileLoadedAsync) {
        Write-Host (Get-Color-String $issue)
    }
}

function Get-Color-String {
    param (
        [Parameter(Mandatory)]
        [string] $in
    )
    $handler = Get-Command -Name 'Get-Color-String-Catppucci' -CommandType Function -ErrorAction SilentlyContinue
    if ($null -ne $handler) {
        return (Get-Color-String-Catppucci -in $in)
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
                Get-Profile-Issues
            }
        }
        catch {
            # Record and continue
            $global:ProfileIssues += "Async init handler error: $($_.Exception.Message)"
        }
    } | Out-Null
}