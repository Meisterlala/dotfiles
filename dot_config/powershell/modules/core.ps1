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
        Write-Warning $issue
    }
}

function Get-Profile-Async {
    # Render all errors
    foreach ($issue in $global:ProfileLoadedAsync) {
        Write-Host $issue
    }
}

function Import-File {
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )
    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "File not found: $Path"
        }

        . $resolvedPath
        Write-Verbose "Imported file: $resolvedPath"
    }
    catch {
        $message = "Failed to import '$Path': $($_.Exception.Message)"
        $global:ProfileIssues += $message
    }
}


# Schedules module/script loading to occur asynchronously during idle time.
# Each queued script is executed one-at-a-time on each idle event, which keeps
# the initial prompt responsive.
function Start-AsyncModuleInitialization {
    param(
        [Parameter(Mandatory)]
        [hashtable] $FilePaths
    )
    # Avoid double registration if called more than once
    if (Get-Variable -Name '__initQueue' -Scope Global -ErrorAction SilentlyContinue) {
        return
    }

    $global:__initQueue = New-Object System.Collections.Queue
    foreach ($file in $FilePaths.Keys) { 
        [void]$global:__initQueue.Enqueue(@{
                Name = $file
                Path = $FilePaths[$file]
            }) 
    }


    # Register idle handler; hidden from Get-EventSubscriber with -SupportEvent
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -SupportEvent -Action {
        try {
            if ($global:__initQueue.Count -gt 0) {
                $file = $global:__initQueue.Dequeue()
                $moduleTime = [System.Diagnostics.Stopwatch]::StartNew()

                try {
                    New-Module -Name $file.Name -ScriptBlock { 
                        . $args[0]
                    } -ArgumentList $file.Path | Import-Module -Global -DisableNameChecking
                }
                catch {
                    $global:ProfileIssues += "Async init failed (${$file.Name}): $($_.Exception.Message)"
                    return
                }

                $moduleTime.Stop() 

                $global:ProfileLoadedAsync += "Loaded $($file.Name) ($elapsedMs ms) from $($file.Path)"
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


                Get-Profile-Issues
            }
        }
        catch {
            # Record and continue
            $global:ProfileIssues += "Async init handler error: $($_.Exception.Message)"
        }
    } | Out-Null
}