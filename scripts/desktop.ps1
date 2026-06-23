param(
    [switch]$Build,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Wait
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$project = Join-Path $root "apps\desktop\TerminalAi.Desktop\TerminalAi.Desktop.csproj"
$exe = Join-Path $root "apps\desktop\TerminalAi.Desktop\bin\Debug\net8.0-windows\TerminalAi.Desktop.exe"

function Stop-Desktop {
    $targets = @(Get-Process -Name "TerminalAi.Desktop" -ErrorAction SilentlyContinue)
    foreach ($process in $targets) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Write-Host "Stopped TerminalAi.Desktop process: $($process.Id)" -ForegroundColor Green
        } catch {
            Write-Host "Failed to stop TerminalAi.Desktop process $($process.Id): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

if ($Stop -or $Restart) {
    Stop-Desktop
    if ($Stop -and -not $Restart) { return }
}

if ($Build -or -not (Test-Path -LiteralPath $exe)) {
    dotnet build $project
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Test-Path -LiteralPath $exe)) {
    throw "TerminalAi.Desktop executable was not found after build: $exe"
}

$process = Start-Process -FilePath $exe -ArgumentList @("--root", $root) -WorkingDirectory $root -PassThru
Write-Host "TerminalAi.Desktop started: $($process.Id)" -ForegroundColor Green
Write-Host "Stop it from tray menu, or run:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$root\scripts\desktop.ps1`" -Stop"

if ($Wait) {
    try {
        Wait-Process -Id $process.Id
    } finally {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
