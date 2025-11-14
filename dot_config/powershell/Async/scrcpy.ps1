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
            Start-Sleep -Seconds 1
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

function Start-Scrcpy
{
    param(
        # Use -Webcam to enable webcam mode
        [switch]$Webcam,
        # Optionally specify the V4L2 device for webcam mode
        [string]$V4l2Device = "/dev/video0",
        # Specify the camera ID for webcam mode
        [int]$CameraId = 0,
        # Specify the maximum FPS
        [int]$MaxFps = 60
    )

    $scrcpyArgs = @(
        "--video-codec=h264",
        "--video-bit-rate=8M",
        "--audio-bit-rate=128K",
        "--mic-camcorder",
        "--max-fps=$MaxFps"
    )

    if ($Webcam)
    {
        $scrcpyArgs += "--v4l2-sink=$V4l2Device", "--video-source=camera", "--camera-id=$CameraId", "--no-video-playback", "--camera-size=1920x1080"
    }


    # Run Link-ScrcpyToVirtualMic in the background
    if ($global:os -eq 'linux')
    {
        Start-Job -ScriptBlock {

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
                        Start-Sleep -Seconds 1
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


            Link-ScrcpyToVirtualMic }
    }
    # Start scrcpy and get the process object
    Start-Process "scrcpy" -ArgumentList $scrcpyArgs -Wait
}

