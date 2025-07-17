k3d completion powershell | Out-String | Invoke-Expression
pv-migrate completion powershell | Out-String | Invoke-Expression
flux completion powershell | Out-String | Invoke-Expression

$env:EDITOR="nvim"
$env:GEMINI_API="AIzaSyCKiR-bb51iqvAPDntOA3AXioZBXj9JLkE"
$env:TAVILY_API_KEY="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"
#$env:OPENROUTER_API_KEY="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"
#$env:DOCKER_HOST=$(docker context inspect --format '{{.Endpoints.docker.Host}}')


$env:Path += ';Z:\replay_uploader\bin'

{{- template "powershell_profile.ps1.tmpl" . -}}
{{ joinPath .chezmoi.sourceDir "encrypted_api_keys.ps1.tmpl.age" | include | decrypt | template }}
