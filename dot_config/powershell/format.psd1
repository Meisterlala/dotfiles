$settings = @{
  IncludeRules = @("PSPlaceOpenBrace", "PSUseConsistentIndentation")
  Rules = @{
    PSPlaceOpenBrace = @{
      Enable = $true
      OnSameLine = $false
    }
    PSUseConsistentIndentation = @{
      Enable = $true
    }
  }
}
