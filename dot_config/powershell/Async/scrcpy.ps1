function Link-ScrcpyToVirtualMic
{
    param(
        [string]$AppNodeName = "scrcpy",
        [string]$VirtualMicName = "scrcpySource"
    )

    # wait until both nodes exist
    do
    {
        $nodes = pw-cli ls Node
        $appExists = $nodes -match "node.name = `"$AppNodeName`""
        $micExists = pw-link -i | Select-String $VirtualMicName

        if (-not ($appExists -and $micExists))
        {
            Start-Sleep -Milliseconds 200
        }
    } until ($appExists -and $micExists)

    # remove existing links from the app
    $nodes = pw-cli ls Node
    $appNodeId = $nodes | Select-String "node.name = `"$AppNodeName`"" | ForEach-Object {
        if ($_.Line -match 'id (\d+),')
        { $matches[1] 
        }
    }
    $links = pw-cli ls Link
    $linkIdsToRemove = $links | ForEach-Object {
        if ($_ -match 'id (\d+),')
        { $linkId = $matches[1] 
        }
        $outputNodeMatch = $_ -match 'link\.output\.node = "(\d+)"'
        $inputNodeMatch = $_ -match 'link\.input\.node = "(\d+)"'
        if ($outputNodeMatch -and $matches[1] -eq $appNodeId)
        { $linkId 
        } elseif ($inputNodeMatch -and $matches[2] -eq $appNodeId)
        { $linkId 
        }
    }
    foreach ($linkId in $linkIdsToRemove | Where-Object { $_ })
    {
        pw-link -d $linkId | Out-Null
    }

    # create new links quietly
    pw-link "${AppNodeName}:output_FL" "${VirtualMicName}:input_FL" | Out-Null
    pw-link "${AppNodeName}:output_FR" "${VirtualMicName}:input_FR" | Out-Null
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
    Start-Process -FilePath "bash" -ArgumentList "-c `"$cmd`"" -NoNewWindow
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

        # Launch scrcpy
        Start-Process "scrcpy" -ArgumentList $scrcpyArgs -Wait
    } while ($Loop)
}




