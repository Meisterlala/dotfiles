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

