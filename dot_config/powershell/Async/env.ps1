# Set Enviorment Variables

# pnpm
$PNPM_HOME = Join-Path $HOME ".local/share/pnpm"
if (Test-Path -Path $PNPM_HOME) {
    if ($IsWindows) {
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $PNPM_HOME })) {
            $env:PATH = "$env:PATH;$PNPM_HOME"
        }
    } else {
        if (-not ($env:PATH -split ':' | Where-Object { $_ -eq $PNPM_HOME })) {
            $env:PATH = "${PNPM_HOME}:$env:PATH"
        }
    }
}

# cargo
$CARGO_BIN = Join-Path $HOME ".cargo/bin"
if (Test-Path -Path $CARGO_BIN) {
    if ($IsWindows) {
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $CARGO_BIN })) {
            $env:PATH = "$env:PATH;$CARGO_BIN"
        }
    } else {
        if (-not ($env:PATH -split ':' | Where-Object { $_ -eq $CARGO_BIN })) {
            $env:PATH = "${CARGO_BIN}:$env:PATH"
        }
    }
}

# Set SOPS Key if it exists
if (Test-Path -Path (Join-Path $HOME ".config/age/sops")) {
    $env:SOPS_AGE_KEY_FILE = Join-Path $HOME ".config/age/sops"
}
