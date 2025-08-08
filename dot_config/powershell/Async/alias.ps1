# Aliases

### Sudo
function sudo-last {
    $history = Get-History -Count 3

    if ($history.Count -lt 1) {
        Write-Host (Get-Color-String "<Peach>No previous command found.<Clear>")
        return
    }

    $lastCommand = $history[-1].CommandLine

    if ([string]::IsNullOrWhiteSpace($lastCommand)) {
        Write-Host (Get-Color-String "<Peach>Last command was empty.<Clear>")
        return
    }

    Invoke-Expression "sudo $lastCommand"
}
Set-Alias -Name 's!' -Value sudo-last | Out-Null
Set-Alias -Name 's!!' -Value sudo-last | Out-Null



### EZA
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function Get-Eza-With-Color {
        param (
            [Parameter(ValueFromRemainingArguments = $true)]
            [string[]]$Args
        )
        eza --icons=auto --color=always --color-scale=size -h @Args
    }
    Set-Alias -Name ls -Value Get-Eza-With-Color | Out-Null
}

### Measure in a new Terminal
function Measure-Script-Separate {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath)) {
        throw "Script file '$ScriptPath' does not exist."
    }

    # Compose the command to run inside the new pwsh process
    $pwshCommand = @"
Import-Module PSProfiler -ErrorAction Stop
Measure-Script -Path '$ScriptPath'
"@

    # Start new pwsh process with -NoProfile and run the above command
    $result = pwsh -NoProfile -Command $pwshCommand

    return $result
}

### Reload
function Reload-Profile {
    . $PROFILE.CurrentUserAllHosts
}

# yay no confirm alias
function Invoke-yay-no-confirm {
    param (
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
    yay --noconfirm @Args
}

Set-Alias -Name yyay -Value Invoke-yay-no-confirm | Out-Null


function Start-Scrcpy() {
    param(
        # Use -Webcam to enable webcam mode
        [switch]$Webcam
    )

    $IP = "pocof2"

    $args = @(
        "--video-codec=h264",
        "--video-bit-rate=16M",
        "--audio-bit-rate=128K",
        "--max-fps=60"
        "--v4l2-sink=/dev/video0"
        "--camera-size=1920x1080"
    )

    if ($Webcam) {
        $args += "--video-source=camera", "--camera-id=0", "--no-video-playback", "--camera-size=1920x1080"
    }


    # Start scrcpy and get the process object
    Start-Process "scrcpy" -ArgumentList $args -Wait
}
