# .githooks/install.ps1 — sets core.hooksPath so the .githooks/ folder is active.
# Run once after cloning: pwsh -File .githooks/install.ps1   (or)   powershell -File .githooks/install.ps1
Set-Location (& git rev-parse --show-toplevel)
& git config core.hooksPath .githooks
Write-Host "core.hooksPath set to .githooks/. Pre-commit hooks active on this clone."
