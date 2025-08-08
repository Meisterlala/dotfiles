Import-Module Catppuccin -Global
$global:Flavor = $catppuccin['Frappe']


function Get-ColorStringCatppuccin {
	param (
		[Parameter(Mandatory)]
		[string] $in
	)
	$tagPattern = '<([A-Za-z0-9]+)>'

	if (-not $global:Flavor) {
		return [regex]::Replace($in, $tagPattern, '')
	}

	$tagMatches = [regex]::Matches($in, $tagPattern)
	if ($tagMatches.Count -eq 0) {
		return $in
	}

	$result = New-Object System.Text.StringBuilder
	$lastIndex = 0

	foreach ($m in $tagMatches) {
		[void]$result.Append($in.Substring($lastIndex, $m.Index - $lastIndex))
		$name = $m.Groups[1].Value
		if ($name -ieq 'Clear') {
			# Reset only the foreground color to terminal default
			[void]$result.Append("$([char]27)[39m")
		}
		else {
			$colourObject = $global:Flavor.$name
			if ($null -ne $colourObject) {
				[void]$result.Append($colourObject.Foreground())
			}
		}
		$lastIndex = $m.Index + $m.Length
	}

	if ($lastIndex -lt $in.Length) {
		[void]$result.Append($in.Substring($lastIndex))
	}

	return $result.ToString()
}


$Colors = @{
	# Largely based on the Code Editor style guide
	# Emphasis, ListPrediction and ListPredictionSelected are inspired by the Catppuccin fzf theme
	
	# Powershell colours
	ContinuationPrompt     = $Flavor.Teal.Foreground()
	Emphasis               = $Flavor.Red.Foreground()
	Selection              = $Flavor.Surface0.Background()
	
	# PSReadLine prediction colours
	InlinePrediction       = $Flavor.Overlay0.Foreground()
	ListPrediction         = $Flavor.Mauve.Foreground()
	ListPredictionSelected = $Flavor.Surface0.Background()

	# Syntax highlighting
	Command                = $Flavor.Blue.Foreground()
	Comment                = $Flavor.Overlay0.Foreground()
	Default                = $Flavor.Text.Foreground()
	Error                  = $Flavor.Red.Foreground()
	Keyword                = $Flavor.Mauve.Foreground()
	Member                 = $Flavor.Rosewater.Foreground()
	Number                 = $Flavor.Peach.Foreground()
	Operator               = $Flavor.Sky.Foreground()
	Parameter              = $Flavor.Pink.Foreground()
	String                 = $Flavor.Green.Foreground()
	Type                   = $Flavor.Yellow.Foreground()
	Variable               = $Flavor.Lavender.Foreground()
}

# Set the colours
Set-PSReadLineOption -Colors $Colors

# The following colors are used by PowerShell's formatting
# Again PS 7.2+ only
$global:PSStyle.Formatting.Debug = $Flavor.Sky.Foreground()
$global:PSStyle.Formatting.Error = $Flavor.Red.Foreground()
$global:PSStyle.Formatting.ErrorAccent = $Flavor.Blue.Foreground()
$global:PSStyle.Formatting.FormatAccent = $Flavor.Teal.Foreground()
$global:PSStyle.Formatting.TableHeader = $Flavor.Rosewater.Foreground()
$global:PSStyle.Formatting.Verbose = $Flavor.Yellow.Foreground()
$global:PSStyle.Formatting.Warning = $Flavor.Peach.Foreground()

