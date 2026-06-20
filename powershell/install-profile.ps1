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
$content = if (Test-Path $profilePath) { Get-Content -Raw -LiteralPath $profilePath } else { "" }

if ($content -notlike "*$HelperProfile*") {
    $newContent = ($content.TrimEnd() + "`r`n`r`n# terminal-ai-helper`r`n$line`r`n").TrimStart()
    try {
        Set-Content -LiteralPath $profilePath -Value $newContent -Encoding UTF8 -ErrorAction Stop
        Write-Host "Installed terminal-ai-helper into PowerShell profile:" -ForegroundColor Green
        Write-Host "  $profilePath"
    } catch {
        Write-Host "Failed to write PowerShell profile:" -ForegroundColor Red
        Write-Host "  $profilePath"
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "Run this command manually in your normal PowerShell session:" -ForegroundColor Yellow
        Write-Host "  Add-Content -Path `"$profilePath`" -Value '# terminal-ai-helper'"
        Write-Host "  Add-Content -Path `"$profilePath`" -Value '$line'"
        Write-Host ""
        Write-Host "Or use the no-profile launcher in this project:" -ForegroundColor Yellow
        Write-Host "  $((Split-Path -Parent (Split-Path -Parent $PSCommandPath)))\terminal-ai-helper.cmd"
        exit 1
    }
}
else {
    Write-Host "terminal-ai-helper is already installed in:" -ForegroundColor Yellow
    Write-Host "  $profilePath"
}

Write-Host "Restart PowerShell or run this now:"
Write-Host "  $line"
