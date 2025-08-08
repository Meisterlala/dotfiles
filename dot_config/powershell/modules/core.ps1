# Core functions
function Get-OS {
    if ($env:OS -eq "Windows_NT") {
        return "windows"
    }
    else {
        return "linux"
    }
}

function Import-File {
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )
    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "File not found: $Path"
        }

        . $resolvedPath
        Write-Verbose "Imported file: $resolvedPath"
    }
    catch {
        $message = "Failed to import '$Path': $($_.Exception.Message)"
        $global:ProfileIssues += $message
    }
}