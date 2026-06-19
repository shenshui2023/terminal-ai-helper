$script:TaihRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:TaihCli = Join-Path $script:TaihRoot "bin\taih.js"

function Invoke-TerminalAiHelper {
    param(
        [ValidateSet("explain", "complete", "fix")]
        [string]$Mode = "explain",
        [string]$Text
    )

    if (-not $Text) {
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$Text, [ref]$null)
    }

    if (-not $Text.Trim()) {
        Write-Host "`nCurrent command is empty." -ForegroundColor Yellow
        return
    }

    $env:TAIH_SHELL = "PowerShell $($PSVersionTable.PSVersion)"
    node $script:TaihCli $Mode --json -- $Text | ConvertFrom-Json
}

function Show-TerminalAiUsage {
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)
    Write-Host ""
    try {
        $result = node $script:TaihCli explain $buffer
        Write-Host $result -ForegroundColor Cyan
    }
    catch {
        Write-Host "AI usage help failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

function Complete-TerminalAiCommand {
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)
    if (-not $buffer.Trim()) {
        return
    }

    Write-Host ""
    try {
        $json = node $script:TaihCli complete --json $buffer
        $result = $json | ConvertFrom-Json
        if ($result.completion) {
            Write-Host "AI completion: $($result.completion)" -ForegroundColor Green
            Write-Host "Summary: $($result.summary)" -ForegroundColor DarkGray
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result.completion)
        }
        else {
            Write-Host "AI returned no direct completion." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "AI completion failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

Set-PSReadLineKeyHandler -Chord "Alt+/" -ScriptBlock { Show-TerminalAiUsage }
Set-PSReadLineKeyHandler -Chord "Ctrl+Spacebar" -ScriptBlock { Complete-TerminalAiCommand }

Write-Host "terminal-ai-helper loaded: Alt+/ shows usage, Ctrl+Space inserts AI completion." -ForegroundColor DarkCyan
