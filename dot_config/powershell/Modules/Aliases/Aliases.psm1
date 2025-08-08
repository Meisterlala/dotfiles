# Aliases and helper functions

if ($IsLinux) {
    function Invoke-SudoLast {
        $history = Get-History -Count 3
        if ($history.Count -lt 1) { Write-Host "No previous command found."; return }
        $lastCommand = $history[-1].CommandLine
        if ([string]::IsNullOrWhiteSpace($lastCommand)) { Write-Host "Last command was empty."; return }
        Invoke-Expression "sudo $lastCommand"
    }
    Set-Alias -Name 's!' -Value Invoke-SudoLast | Out-Null
    Set-Alias -Name 's!!' -Value Invoke-SudoLast | Out-Null
}

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function Get-DirectoryColored {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
        eza --icons=auto --color=always --color-scale=size -h @Args
    }
    Set-Alias -Name ls -Value Get-DirectoryColored | Out-Null
}

function Import-Profile { if (Test-Path $PROFILE.CurrentUserAllHosts) { . $PROFILE.CurrentUserAllHosts } }
Set-Alias -Name Reload-Profile -Value Import-Profile | Out-Null

function Start-Scrcpy {
    param([switch]$Webcam)
    $scrcpyArgs = @("--video-codec=h264", "--video-bit-rate=16M", "--audio-bit-rate=128K", "--max-fps=60", "--v4l2-sink=/dev/video0", "--camera-size=1920x1080")
    if ($Webcam) { $scrcpyArgs += "--video-source=camera", "--camera-id=0", "--no-video-playback", "--camera-size=1920x1080" }
    if (Get-Command scrcpy -ErrorAction SilentlyContinue) { Start-Process "scrcpy" -ArgumentList $scrcpyArgs -Wait } else { Write-Warning "scrcpy not found. Please install it first." }
}


# yay no confirm alias
if (Get-Command yay -ErrorAction SilentlyContinue) {
    function yay-no-confirm {
        param (
            [Parameter(ValueFromRemainingArguments = $true)]
            [string[]]$Args
        )
        yay --noconfirm @Args
    }

    Set-Alias -Name yyay -Value yay-no-confirm | Out-Null
}

function Measure-Script {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        throw "Script '$Path' does not exist."
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { & $Path } finally {
        $sw.Stop();
        Write-Host ("{0} ms" -f [math]::Round($sw.Elapsed.TotalMilliseconds))
    }
}