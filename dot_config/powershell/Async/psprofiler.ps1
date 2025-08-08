# Check if PSProfiler is installed
if (-not (Get-Module -ListAvailable -Name PSProfiler)) {
    try {
        Write-Host "Installing PSProfiler..."
        Install-Module PSProfiler -Scope CurrentUser -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to install PSProfiler: $_"
    }
}

# Try to import the module
try {
    Import-Module PSProfiler -ErrorAction Stop
}
catch {
    Write-Warning "⚠ Could not load PSProfiler: $_"
}

