PowerShell Profile Structure

Overview

- Entry point: Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl only sources ~/.config/powershell/main.ps1
- main.ps1 orchestrates modular imports and shows a startup summary of optional tools.

Layout

- ~/.config/powershell/main.ps1.tmpl: imports modules, loads secrets, prints timing/summary
- ~/.config/powershell/api_keys.ps1: optional, decrypted by chezmoi (encrypted_api_keys.ps1.tmpl.age)
- ~/.config/powershell/Modules/
  - Profile.Core/Profile.Core.psm1: Add-ProfileIssue, PSReadLine baseline
  - Profile.Prompt/Profile.Prompt.psm1: Prompt/Oh My Posh init
  - Profile.Zoxide/Profile.Zoxide.psm1: Initialize-Zoxide (lazy init)
  - Profile.Completions/Profile.Completions.psm1: PSCompletions import and bash completion bridge
  - Profile.Chezmoi/Profile.Chezmoi.psm1: chezmoi completions, Edit-Chezmoi/alias
  - Profile.Aliases/Profile.Aliases.psm1: aliases, helper functions

Guidelines

- Add features as a new module under Modules/Profile.<Feature>/<Feature>.psm1
- Export only the functions you want public via Export-ModuleMember
- Keep module imports non-failing: use -ErrorAction SilentlyContinue from main.ps1
- For heavy initializers, expose Initialize-<Feature> and call it lazily or from a background job

Performance tips

- Avoid network installs in profile; do installs via run_onchange/run_once scripts
- Keep imports light; prefer on-demand functions over eager initialization
- Use Start-Job for background warmups that don’t need the interactive session context

Lazy loading patterns

- Define functions that import their module on first use (dot-source or Import-Module inside the function)
- Schedule Start-Job warmups (example: Initialize-Zoxide) right after startup

Security

- Never place secrets in profile files; keep them in encrypted templates and load the rendered file only

Extending

- Create Profile.<NewFeature>/<NewFeature>.psm1 and add this to main.ps1:
  Import-Module (Join-Path $modulesBase "Profile.<NewFeature>/<NewFeature>.psm1") -ErrorAction SilentlyContinue
  # optional: Add-ProfileIssue if Initialize-<NewFeature> missing or not installed
