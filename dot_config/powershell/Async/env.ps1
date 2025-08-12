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


# Test for cargo bin folder and add it (cross-platform)
$CARGO_BIN = Join-Path $HOME ".cargo/bin"
if (Test-Path -Path $CARGO_BIN) {
    if ($global:os -eq "windows") {
        $env:PATH += ";$CARGO_BIN"
    } else {
        $env:PATH += ":$CARGO_BIN"
    }
}

