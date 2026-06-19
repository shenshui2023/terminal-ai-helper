param(
    [string]$ExtensionPath = "E:\3.13-aliyun-codex\5.2\terminal-ai-helper\integrations\vscode\terminal-ai-helper"
)

function L {
    param([string]$Text)
    $evaluator = {
        param($Match)
        [string][char]([Convert]::ToInt32($Match.Groups[1].Value, 16))
    }
    return [regex]::Replace($Text, '\\u([0-9a-fA-F]{4})', [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

$target = Join-Path $env:USERPROFILE ".vscode\extensions\terminal-ai-helper-local"

if (-not (Test-Path $ExtensionPath)) {
    throw ((L '\u627e\u4e0d\u5230 VS Code \u6269\u5c55\u76ee\u5f55\uff1a') + $ExtensionPath)
}

if (Test-Path $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
}

New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
Copy-Item -Path $ExtensionPath -Destination $target -Recurse -Force

Write-Host (L 'VS Code \u6269\u5c55\u5df2\u590d\u5236\u5230\uff1a') -ForegroundColor Green
Write-Host "  $target"
Write-Host (L '\u8bf7\u91cd\u542f VS Code\uff0c\u7136\u540e\u5728\u547d\u4ee4\u9762\u677f\u6216\u53f3\u952e\u83dc\u5355\u4e2d\u4f7f\u7528\uff1a')
Write-Host (L '  \u7ec8\u7aef AI \u52a9\u624b\uff1a\u89e3\u91ca\u9009\u4e2d\u6587\u672c')
