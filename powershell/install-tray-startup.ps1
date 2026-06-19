param(
    [string]$TrayScript = "E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1"
)

function L {
    param([string]$Text)
    $evaluator = {
        param($Match)
        [string][char]([Convert]::ToInt32($Match.Groups[1].Value, 16))
    }
    return [regex]::Replace($Text, '\\u([0-9a-fA-F]{4})', [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

if (-not (Test-Path -LiteralPath $TrayScript)) {
    throw ((L '\u627e\u4e0d\u5230\u6258\u76d8\u811a\u672c\uff1a') + $TrayScript)
}

$startup = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startup "terminal-ai-helper-tray.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
$shortcut.WorkingDirectory = Split-Path -Parent (Split-Path -Parent $TrayScript)
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,167"
$shortcut.Description = "terminal-ai-helper tray"
$shortcut.Save()

Write-Host (L '\u5df2\u521b\u5efa\u5f00\u673a\u81ea\u542f\u6258\u76d8\u5feb\u6377\u65b9\u5f0f\uff1a') -ForegroundColor Green
Write-Host "  $shortcutPath"
Write-Host (L '\u7acb\u5373\u542f\u52a8\u6258\u76d8\uff1a')
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayScript`""
