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
    pw-link --save "${AppNodeName}:output_FL" "${VirtualMicName}:input_FL" | Out-Null
    pw-link --save "${AppNodeName}:output_FR" "${VirtualMicName}:input_FR" | Out-Null
}

function Start-Scrcpy
{
    param(
        # Use -Webcam to enable webcam mode
        [switch]$Webcam,
        # Use -Loop to enable looping mode
        [switch]$Loop,
        # Optionally specify the V4L2 device for webcam mode
        [string]$V4l2Device = "/dev/video0",
        # Specify the camera ID for webcam mode
        [int]$CameraId = 0,
        # Specify the maximum FPS
        [int]$MaxFps = 60
    )

    $scrcpyArgs = @(
        "--video-codec=h264",
        "--video-bit-rate=12M",
        "--audio-bit-rate=128K",
        "--audio-source=mic-camcorder",
        #"--audio-codec=aac",
        "--max-fps=$MaxFps"
    )

    if ($Webcam)
    {
        $scrcpyArgs += "--v4l2-sink=$V4l2Device", "--video-source=camera", "--camera-id=$CameraId", "--no-video-playback", "--camera-size=1920x1080"
    }

    # Start scrcpy and get the process object
    do {
        # Run Link-ScrcpyToVirtualMic in the background
        if ($global:os -eq 'linux')
        {
            $func = ${function:Link-ScrcpyToVirtualMic}.ToString()
            Start-Job -ScriptBlock {
                param($f)
                Invoke-Expression $f
                Link-ScrcpyToVirtualMic
            } -ArgumentList $func
        }
        Start-Process "scrcpy" -ArgumentList $scrcpyArgs -Wait
    } while ($Loop)
}

