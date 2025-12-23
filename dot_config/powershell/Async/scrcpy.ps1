function Link-ScrcpyToVirtualMic
{
    param(
        [string]$App = "scrcpy",
        [string]$Sink = "scrcpy-sink"
    )

    # wait until both nodes exist
    do
    {
        $nodes = pw-cli ls Node
        $appExists = $nodes -match "node.name = `"$App`""
        $sinkExists = $nodes -match "node.name = `"$Sink`""

        if (-not ($appExists -and $sinkExists))
        {
            Start-Sleep -Milliseconds 200
        }
    } until ($appExists -and $sinkExists)

    # Get all nodes
    $Nodes = pw-cli ls Node

    # Function to extract node id by matching a line
    function Get-NodeId($Nodes, $MatchText)
    {
        $NodeId = 0
        $CurrentId = 0
        foreach ($Line in $Nodes)
        {
            if ($Line -match 'id (\d+),')
            {
                $CurrentId = $matches[1]
            }
            if ($Line -match [regex]::Escape($MatchText))
            {
                $NodeId = $CurrentId
                break
            }
        }
        return $NodeId
    }


    # Get app node id
    $AppId = Get-NodeId $Nodes "application.name = `"$App`""

    # Get sink node id
    $SinkId = Get-NodeId $Nodes "node.name = `"$Sink`""

    $linkList = pw-link -lI
    foreach ($link in $linkList)
    {
        if ($link -match "\b$AppId\b")
        {
            # unlink the old link
            if ($link -match '(\d+):')
            {
                $linkId = $matches[1]
                Write‑Host "Removing old link id $linkId"
                pw‑link ‑d $linkId
            }
        }
    }

    pw-link -L $AppId $SinkId | Out-Null

}


function Start-OBS
{
    param(
        [string]$OBSPath = "obs",
        [string]$Profile = "",
        [string]$Scene = "",
        [switch]$StartVirtualCam,
        [switch]$StartRecording,
        [switch]$MinimizeToTray
    )

    # Check if OBS is already running
    if (Get-Process -Name "obs" -ErrorAction SilentlyContinue)
    {
        Write-Host "OBS is already running."
        return
    }

    $args = @()

    if ($StartVirtualCam)
    { $args += "--startvirtualcam" 
    }
    if ($StartStreaming)
    { $args += "--startstreaming" 
    }
    if ($StartRecording)
    { $args += "--startrecording" 
    }
    if ($Profile)
    { $args += "--profile `"$Profile`"" 
    }
    if ($Scene)
    { $args += "--scene `"$Scene`"" 
    }
    if ($MinimizeToTray)
    { $args += "--minimize-to-tray" 
    }
    # Build command string
    $cmd = "$OBSPath $($args -join ' ') > /dev/null 2>&1 &"

    # Start OBS completely detached
    Start-Process -FilePath "bash" -ArgumentList "-c `"$cmd`""
}

function Start-Scrcpy
{
    param(
        # Use -Webcam to enable webcam mode
        [switch]$Webcam,
        # Use -Loop to enable looping mode
        [switch]$Loop,
        # Start OBS aswell
        [switch]$OBS,
        # Optionally specify the V4L2 device for webcam mode
        [string]$V4l2Device = "/dev/video8",
        # Specify the camera ID for webcam mode
        [int]$CameraId = 0,
        # Specify the maximum FPS
        [int]$MaxFps = 30,
        # Resolution
        [string]$Resolution = "1920x1080"
    )

    $lock = "$env:TEMP\scrcpy.lock"
    Remove-Item $lock -ErrorAction SilentlyContinue

    $scrcpyArgs = @(
        "--video-codec=h264",
        "--video-bit-rate=12M",
        "--audio-bit-rate=128K",
        "--audio-source=mic-camcorder",
        #"--audio-codec=aac",
        "--max-fps=$MaxFps"
    )

    # Configure webcam mode if specified
    if ($Webcam)
    {
        $scrcpyArgs += "--video-source=camera", "--camera-id=$CameraId", "--no-video-playback", "--camera-size=$Resolution"

        # Add V4L2 sink argument for Linux
        if ($global:os -eq 'linux')
        {
            $scrcpyArgs += "--v4l2-sink=$V4l2Device";
        }
    }

    # Start OBS if specified
    if ($OBS)
    {
        # OBS integration is not supported on Windows
        if ($global:os -eq 'windows')
        {
            Write-Error "OBS integration is not supported on Windows"
            return
        }

        Start-OBS -StartVirtualCam -MinimizeToTray
    }

    # Start scrcpy in a loop, if specifed
    do
    {
        # On Linux, link scrcpy audio to virtual mic in a background job
        if ($global:os -eq 'linux')
        {
            $func = ${function:Link-ScrcpyToVirtualMic}.ToString()
            Start-Job -ScriptBlock {
                param($f)
                Invoke-Expression $f
                Link-ScrcpyToVirtualMic
            } -ArgumentList $func
        }

        # Launch scrcpy and capture process for exit code checking
        $proc = Start-Process "scrcpy" -ArgumentList $scrcpyArgs -PassThru
        $proc.WaitForExit()
        $exit = $proc.ExitCode

        # If scrcpy was killed by a command, break the loop; otherwise continue (e.g., on crash)
        if ($global:os -eq 'linux')
        {
            # Common Linux signal-derived exit codes: 130 (SIGINT), 143 (SIGTERM), 137 (SIGKILL)
            if ($exit -in 130, 143, 137)
            { break 
            }
        } else
        {
            # On Windows, a normal close typically returns 0, while crashes are non-zero
            if ($exit -eq 0)
            { break 
            }
        }

        # Check for lock file to determine whether to continue looping
        if (-Not (Test-Path $lock))
        {
            break
        }

    } while ($Loop)
}




