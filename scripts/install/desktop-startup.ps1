param(
    [switch]$Build
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$project = Join-Path $root "apps\desktop\TerminalAi.Desktop\TerminalAi.Desktop.csproj"
$exe = Join-Path $root "apps\desktop\TerminalAi.Desktop\bin\Debug\net8.0-windows\TerminalAi.Desktop.exe"

if ($Build -or -not (Test-Path -LiteralPath $exe)) {
    dotnet build $project
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Test-Path -LiteralPath $exe)) {
    throw "TerminalAi.Desktop executable was not found after build: $exe"
}

$startup = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startup "TerminalAi.Desktop.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exe
$shortcut.Arguments = "--root `"$root`""
$shortcut.WorkingDirectory = $root
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,167"
$shortcut.Description = "TerminalAi.Desktop"
$shortcut.Save()

Write-Host "Created TerminalAi.Desktop startup shortcut:" -ForegroundColor Green
Write-Host "  $shortcutPath"
Write-Host "Start now:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$root\scripts\desktop.ps1`""
