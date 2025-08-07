# Completions module: PSCompletions and Bash bridge

try {
    if (Get-Module -ListAvailable -Name PSCompletions) {
        if (-not (Get-Module PSCompletions)) {
            Import-Module PSCompletions -ErrorAction Stop
        }
        psc menu config enable_menu_enhance 0 *> $null
    }
}
catch {}

function Register-BashCompletion {
    param([string]$Command)
    Register-ArgumentCompleter -Native -CommandName $Command -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $cmd = $commandAst.GetCommandName()
        $helper = Join-Path $HOME ".config/powershell/bash_complete.sh"
        $results = @()
        if (Test-Path $helper) {
            $results = @(bash $helper  $cmd "$cmd $wordToComplete")
        }
        foreach ($item in $results) {
            [System.Management.Automation.CompletionResult]::new($item, $item, 'ParameterValue', $item)
        }
    }
}

function Import-BashCompletionsToPwsh {
    $commands = @()
    if (Test-Path '/usr/share/bash-completion/bash_completion') {
        $commands = bash -c 'source /usr/share/bash-completion/bash_completion; complete -p' |
        ForEach-Object { if ($_ -match 'complete .* ([\w.-]+)$') { $matches[1] } }
        $completionFiles = Get-ChildItem -Path '/usr/share/bash-completion/completions' -File |
        Where-Object { -not $_.Name.StartsWith('_') } |
        ForEach-Object { $_.Name }
        $commands = ($commands + $completionFiles) |
        Where-Object { $_ -ne '-D' } | Sort-Object -Unique
    }
    foreach ($cmd in $commands) { Register-BashCompletion $cmd }
}

# Arch-specific completions for pacman/yay on Linux
if ($IsLinux) {
    if (Get-Command pacman -ErrorAction SilentlyContinue) {
        Register-ArgumentCompleter -Native -CommandName 'pacman' -ScriptBlock { param($wordToComplete) } 
    }
    if (Get-Command yay -ErrorAction SilentlyContinue) {
        Register-ArgumentCompleter -Native -CommandName 'yay' -ScriptBlock { param($wordToComplete) } 
    }
}

Export-ModuleMember -Function Register-BashCompletion, Import-BashCompletionsToPwsh


