param(
    [switch]$Build
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$project = Join-Path $root "apps\desktop\TerminalAi.Desktop\TerminalAi.Desktop.csproj"

if ($Build) {
    dotnet build $project
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$startup = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startup "TerminalAi.Desktop.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "dotnet.exe"
$shortcut.Arguments = "run --project `"$project`" -- --root `"$root`""
$shortcut.WorkingDirectory = $root
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,167"
$shortcut.Description = "TerminalAi.Desktop"
$shortcut.Save()

Write-Host "Created TerminalAi.Desktop startup shortcut:" -ForegroundColor Green
Write-Host "  $shortcutPath"
Write-Host "Start now:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$root\scripts\desktop.ps1`""
