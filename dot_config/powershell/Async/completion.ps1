# Ensure PSCompletions is installed and loaded
if (-not (Get-Module -ListAvailable -Name PSCompletions)) {
    try {
        Install-Module PSCompletions -Scope CurrentUser -Force -ErrorAction Stop
    }
    catch {
        $global:ProfileIssues += "<Red>Failed to install PSCompletions<Clear>: $_"
    }
}

# Load the module if installed successfully
if (Get-Module -ListAvailable -Name PSCompletions) {
    # TODO: somehow broken??
    Import-Module PSCompletions
}

Function Get-ArgumentCompleters {
    $getExecutionContextFromTLS = [PowerShell].Assembly.GetType('System.Management.Automation.Runspaces.LocalPipeline').GetMethod(
        'GetExecutionContextFromTLS',
        [System.Reflection.BindingFlags]'Static,NonPublic'
    )
    $internalExecutionContext = $getExecutionContextFromTLS.Invoke(
        $null,
        [System.Reflection.BindingFlags]'Static, NonPublic',
        $null,
        $null,
        $psculture
    )

    $argumentCompletersPropertyNative = $internalExecutionContext.GetType().GetProperty(
        'NativeArgumentCompleters',
        [System.Reflection.BindingFlags]'NonPublic, Instance'
    )
    $argumentCompletersPropertyCustom = $internalExecutionContext.GetType().GetProperty(
        'CustomArgumentCompleters',
        [System.Reflection.BindingFlags]'NonPublic, Instance'
    )

    $argumentCompleters = $argumentCompletersPropertyNative.GetGetMethod($true).Invoke(
        $internalExecutionContext,
        [System.Reflection.BindingFlags]'Instance, NonPublic, GetProperty',
        $null,
        @(),
        $psculture
    )

    $argumentCompleters = $argumentCompletersPropertyCustom.GetGetMethod($true).Invoke(
        $internalExecutionContext,
        [System.Reflection.BindingFlags]'Instance, NonPublic, GetProperty',
        $null,
        @(),
        $psculture
    )

    foreach ($completer in $argumentCompleters.Keys) {
        $name, $parameter = $completer -split ':'

        [PSCustomObject]@{
            CommandName   = $name
            ParameterName = $parameter
            Definition    = $argumentCompleters[$completer]
        }
    }
}


### Bash Autocomplete
function Register-BashCompletion {
    param(
        # The name of the command to register for completion
        [string]$Command
    )

    Register-ArgumentCompleter -Native -CommandName $Command -ScriptBlock {
        param(
            $wordToComplete,
            $commandAst,
            $cursorPosition
        )
        $cmd = $commandAst.GetCommandName()

        $helper = $global:myFiles.completionHelper
        if (-not (Test-Path $helper)) { 
            $global:ProfileIssues += "Could not find bash_complete.sh at: $helper"
            return Get-ColorString("<Red> Could not find bash_complete.sh helper")
        }

        $results = @(bash $helper  $cmd "$cmd $wordToComplete")

        foreach ($item in $results) {
            [System.Management.Automation.CompletionResult]::new($item, $item, 'ParameterValue', $item)
        }
    }
}

function Get-BashCompletion {
    # Get commands that have registered completions
    $cmds = bash -c 'source /usr/share/bash-completion/bash_completion; complete -p' |
    ForEach-Object {
        if ($_ -match 'complete .* ([\w.-]+)$') {
            $matches[1]
        }
    }

    # Get filenames ignoring those starting with underscore
    $completionFiles = Get-ChildItem -Path '/usr/share/bash-completion/completions' -File |
    Where-Object { -not $_.Name.StartsWith('_') } |
    ForEach-Object { $_.Name }

    # Combine, filter out '-D', and get unique sorted list
    ($cmds + $completionFiles) |
    Where-Object { $_ -ne '-D' } |
    Sort-Object -Unique
}

function Import-BashCompletionIntoPwsh {
    $commands = Get-BashCompletion

    # Write-Host (Get-ColorString "<Green>Registering $($commands.Count) commands for pwsh completion...<Clear>")
    foreach ($cmd in $commands) {
        Register-BashCompletion $cmd
    }
}
function Install-BashCompletion {
    Install-WithYayPacman "bash-completion"
}

if (Test-Path '/usr/share/bash-completion/bash_completion') {
    # Require bash-helper
    if (-not (Test-Path $global:myFiles.completionHelper) )
    {
        $Global:ProfileIssues += "Could not find bash_completion helper"
    } else {
        Import-BashCompletionIntoPwsh
    }
} else {
    $Global:ProfileHints += "<Teal>bash-completion<Clear> not installed. Please install it with <Mauve>Install-BashCompletion"
}


# Global cache
if (-not $global:PackageCache) {
    $global:PackageCache = @{}
}

# Function to fetch and parse packages
function Get-PackageCompletion {
    param (
        [string]$Command
    )

    if (-not $global:PackageCache.ContainsKey($Command)) {
        $output = & $Command -Ss | Out-String

        $pattern = '^(?<repo>\S+)/(?<name>\S+)\s+(?<version>\S+)[^\n]*\n\s+(?<desc>[^\n]+)$'
        $pmatches = [regex]::Matches($output, $pattern, 'Multiline')

        $pkgs = foreach ($match in $pmatches) {
            [PSCustomObject]@{
                Repo        = $match.Groups['repo'].Value
                Name        = $match.Groups['name'].Value
                Version     = $match.Groups['version'].Value.Trim()
                Description = $match.Groups['desc'].Value.Trim()
            }
        }

        $global:PackageCache[$Command] = $pkgs
    }

    return $global:PackageCache[$Command]
}

# Register completions for pacman
Register-ArgumentCompleter -Native -CommandName 'pacman' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $packages = Get-PackageCompletion 'pacman'
    $prefix = [regex]::Escape($wordToComplete)

    $packages |
    Where-Object { $_.Name -match "^$prefix" } |
    Sort-Object -Property Name -Unique |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_.Name,
            $_.Name,
            'ParameterValue',
            "$($_.Description) [$($_.Repo)/$($_.Version)]"
        )
    }
}

# Register completions for yay
Register-ArgumentCompleter -Native -CommandName 'yay' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $packages = Get-PackageCompletion 'yay'
    $prefix = [regex]::Escape($wordToComplete)

    $packages |
    Where-Object { $_.Name -match "^$prefix" } |
    Sort-Object -Property Name -Unique |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_.Name,
            $_.Name,
            'ParameterValue',
            "$($_.Description) [$($_.Repo)/$($_.Version)]"
        )
    }
}

