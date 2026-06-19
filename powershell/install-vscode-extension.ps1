param(
    [string]$ExtensionPath = "E:\3.13-aliyun-codex\5.2\terminal-ai-helper\integrations\vscode\terminal-ai-helper"
)

$target = Join-Path $env:USERPROFILE ".vscode\extensions\terminal-ai-helper-local"

if (-not (Test-Path $ExtensionPath)) {
    throw "Extension path not found: $ExtensionPath"
}

if (Test-Path $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
}

New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
Copy-Item -Path $ExtensionPath -Destination $target -Recurse -Force

Write-Host "VS Code extension copied to:" -ForegroundColor Green
Write-Host "  $target"
Write-Host "Restart VS Code, then use Command Palette:"
Write-Host "  Terminal AI Helper: Explain Selection"
