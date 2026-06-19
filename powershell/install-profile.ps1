param(
    [string]$HelperProfile = "E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1"
)

$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir = Split-Path -Parent $profilePath

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$line = ". `"$HelperProfile`""
$content = Get-Content -Raw -Path $profilePath

if ($content -notlike "*$HelperProfile*") {
    Add-Content -Path $profilePath -Value ""
    Add-Content -Path $profilePath -Value "# terminal-ai-helper"
    Add-Content -Path $profilePath -Value $line
    Write-Host "Installed terminal-ai-helper into PowerShell profile:" -ForegroundColor Green
    Write-Host "  $profilePath"
}
else {
    Write-Host "terminal-ai-helper is already installed in:" -ForegroundColor Yellow
    Write-Host "  $profilePath"
}

Write-Host "Restart PowerShell or run this now:"
Write-Host "  $line"
