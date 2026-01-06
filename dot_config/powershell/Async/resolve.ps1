function Convert-ResolveVideo
{
    param(
        [Parameter(Mandatory)]
        [string] $InputFile,
        [string] $OutputFile,
        [string] $Fps = "30"
    )

    if (-not $OutputFile)
    {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
        $OutputFile = "${base}_davinci.mov"
    }

    try
    {
        ffmpeg -fflags +genpts `
            -hide_banner `
            -i "$InputFile" `
            -r $Fps `
            -c:v dnxhd `
            -profile:v 3 `
            -pix_fmt yuv422p `
            -c:a copy `
            "$OutputFile"

        if ($LASTEXITCODE -ne 0)
        {
            throw "ffmpeg failed"
        }

    } catch
    {
        if (Test-Path $OutputFile)
        {
            Remove-Item $OutputFile -Force
            Write-Host "<Red>Deleted broken file: $OutputFile<Clear>"
        }
        throw
    }
}

function Convert-AllToResolve
{
    param(
        [string] $Fps = "30"
    )

    $videoExts = @(".mp4", ".mov", ".mxf", ".avi")

    $files = Get-ChildItem -File | Where-Object {
        $videoExts -contains $_.Extension.ToLower() -and
        -not $_.Name.EndsWith("_davinci.mov") -and
        -not (Test-Path "$($_.BaseName)_davinci.mov")
    }

    if (-not $files)
    {
        Write-Host(Get-ColorString "<Red>No videos to convert.<Clear>")
        return
    }

    Write-Host "Videos to convert:`n"

    foreach ($f in $files)
    {
        Write-Host(Get-ColorString "  - <Green>$($f.Name)<Clear>")
    }
    Write-Host ""

    foreach ($f in $files)
    {
        $out = "$($f.BaseName)_davinci.mov"
        Write-Host(Get-ColorString "<Teal>Converting $($f.Name) → $out<Clear>")
        Convert-ResolveVideo -InputFile $f.FullName -OutputFile $out -Fps $Fps
    }
}

function Remove-ResolveVideos
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param ()

    $files = Get-ChildItem -File | Where-Object {
        $_.Name.EndsWith("_davinci.mov")
    }

    if (-not $files)
    {
        Write-Host(Get-ColorString "<Red>No resolve videos to delete.<Clear>")
        return
    }

    Write-Host "Resolve videos to delete:`n"

    foreach ($f in $files)
    {
        Write-Host(Get-ColorString "  - <Green>$($f.Name)<Clear>")
    }
    Write-Host ""

    foreach ($f in $files)
    {
        Remove-Item $f.FullName -Force -Confirm:$ConfirmPreference -WhatIf:$WhatIfPreference
    }

    Write-Host(Get-ColorString "All selected resolve videos deleted")
}
