# Set Enviorment Variables

# pnpm
if (Get-Command -Name "pnpm" -ErrorAction SilentlyContinue) {
    $env:PNPM_HOME = Join-Path $HOME ".local/share/pnpm"
    
    if ($global:os -eq "windows") {
        $env:PATH += ";$env:PNPM_HOME"
    } else {
        $env:PATH += ":$env:PNPM_HOME"
    }
}

