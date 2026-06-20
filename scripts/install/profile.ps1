param(
    [string]$HelperProfile = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $HelperProfile) {
    $HelperProfile = Join-Path $root "apps\powershell\profile.ps1"
}

function Ensure-ProfileLine {
    param(
        [string]$ProfilePath,
        [string]$Line
    )

    $profileDir = Split-Path -Parent $ProfilePath
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
    }

    $content = Get-Content -Raw -LiteralPath $ProfilePath
    if ($content -like "*$HelperProfile*" -or $content -like "*terminal-ai-helper\\powershell\\taih-profile.ps1*") {
        Write-Host "terminal-ai-helper is already installed in:" -ForegroundColor Yellow
        Write-Host "  $ProfilePath"
        return $true
    }

    $newContent = ($content.TrimEnd() + "`r`n`r`n# terminal-ai-helper`r`n$Line`r`n").TrimStart()
    Set-Content -LiteralPath $ProfilePath -Value $newContent -Encoding UTF8 -ErrorAction Stop
    Write-Host "Installed terminal-ai-helper into PowerShell profile:" -ForegroundColor Green
    Write-Host "  $ProfilePath"
    return $true
}

$line = ". `"$HelperProfile`""
$targets = @(
    $PROFILE.CurrentUserCurrentHost,
    $PROFILE.CurrentUserAllHosts
) | Where-Object { $_ } | Select-Object -Unique

$lastError = $null
foreach ($target in $targets) {
    try {
        if (Ensure-ProfileLine -ProfilePath $target -Line $line) {
            Write-Host "Restart PowerShell or run this now:"
            Write-Host "  $line"
            exit 0
        }
    } catch {
        $lastError = $_
        Write-Host "Failed to write PowerShell profile:" -ForegroundColor Yellow
        Write-Host "  $target"
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Could not write any PowerShell profile automatically." -ForegroundColor Red
Write-Host "Run this command manually in your normal PowerShell session:" -ForegroundColor Yellow
Write-Host "  Add-Content -Path `"$($PROFILE.CurrentUserCurrentHost)`" -Value '# terminal-ai-helper'"
Write-Host "  Add-Content -Path `"$($PROFILE.CurrentUserCurrentHost)`" -Value '$line'"
Write-Host ""
Write-Host "Or use the no-profile launcher in this project:" -ForegroundColor Yellow
Write-Host "  $root\terminal-ai-helper.cmd"
if ($lastError) { Write-Host $lastError.Exception.Message -ForegroundColor Red }
exit 1
