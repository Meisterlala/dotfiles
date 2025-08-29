# Core functions
function Get-OperatingSystem {
    if ($env:OS -eq "Windows_NT") {
        return "windows"
    }
    else {
        return "linux"
    }
}
$global:os = Get-OperatingSystem

function Show-ProfileIssues {
    # Render all errors
    foreach ($issue in $global:ProfileIssues) {
        Write-Warning (Get-ColorString $issue)
    }
}

function Show-ProfileHints {
    param(
        [string[]] $hints = $Global:ProfileHints
    )

    # Render all errors
    foreach ($issue in $hints) {
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
    if ((Get-OperatingSystem) -ne "windows") {
        Write-Warning "You can only use winget on windows"
        return
    }

    try {
        winget install --exact $name --accept-package-agreements 
    }
    catch {
        throw "Could not install $name with winget: $_"
    }
    Update-Async
}

function Install-WithYayPacman {
    param (
        [Parameter(Mandatory, ValueFromRemainingArguments = $true)]
        [string[]] $Name
    )

    if ((Get-OperatingSystem) -ne "linux") {
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
    Update-Async
}


function install-withapt {
    param (
        [Parameter(Mandatory, ValueFromRemainingArguments = $true)]
        [string[]] $Name
    )

    if ((Get-OperatingSystem) -ne "linux") {
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

