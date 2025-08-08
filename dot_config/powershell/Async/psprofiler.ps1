# Check if PSProfiler is installed
if (-not (Get-Module -ListAvailable -Name PSProfiler)) {
    try {
        Write-Host (Get-Color-String "<Teal>Installing PSProfiler...<Clear>")
        Install-Module PSProfiler -Scope CurrentUser -Force -ErrorAction Stop
    }
    catch {
        Write-Warning (Get-Color-String "<Red>Failed to install PSProfiler<Clear>: $_")
    }
}

# Try to import the module
try {
    Import-Module PSProfiler -ErrorAction Stop
}
catch {
    Write-Warning (Get-Color-String "<Peach>⚠ Could not load PSProfiler<Clear>: $_")
}

