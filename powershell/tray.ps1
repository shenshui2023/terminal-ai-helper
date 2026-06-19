param(
    [string]$ProfileScript = "E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1",
    [int]$ServerPort = 17888
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. $ProfileScript

$script:TaihServerProcess = $null

function Start-TerminalAiServer {
    if ($script:TaihServerProcess -and -not $script:TaihServerProcess.HasExited) {
        [System.Windows.Forms.MessageBox]::Show((L '\u672c\u5730\u670d\u52a1\u5df2\u7ecf\u5728\u8fd0\u884c\u3002'), (L '\u7ec8\u7aef AI \u52a9\u624b')) | Out-Null
        return
    }
    $root = Split-Path -Parent (Split-Path -Parent $ProfileScript)
    $script:TaihServerProcess = Start-Process -FilePath "node" `
        -ArgumentList @("$root\bin\taih.js", "serve", "--port", "$ServerPort") `
        -WindowStyle Hidden `
        -PassThru
    [System.Windows.Forms.MessageBox]::Show(((L '\u672c\u5730\u670d\u52a1\u5df2\u542f\u52a8\uff1a') + "127.0.0.1:$ServerPort"), (L '\u7ec8\u7aef AI \u52a9\u624b')) | Out-Null
}

function Stop-TerminalAiServer {
    if ($script:TaihServerProcess -and -not $script:TaihServerProcess.HasExited) {
        Stop-Process -Id $script:TaihServerProcess.Id -Force
        [System.Windows.Forms.MessageBox]::Show((L '\u672c\u5730\u670d\u52a1\u5df2\u505c\u6b62\u3002'), (L '\u7ec8\u7aef AI \u52a9\u624b')) | Out-Null
    }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$openPanel = $menu.Items.Add((L '\u6253\u5f00\u7ba1\u7406\u9762\u677f'))
$openPanel.Add_Click({ Show-TerminalAiPanel })

$explainClipboard = $menu.Items.Add((L '\u89e3\u91ca\u526a\u8d34\u677f'))
$explainClipboard.Add_Click({ Invoke-TerminalAiClipboard -Mode explain -Window })

$fixClipboard = $menu.Items.Add((L '\u8bca\u65ad\u526a\u8d34\u677f'))
$fixClipboard.Add_Click({ Invoke-TerminalAiClipboard -Mode fix -Window })

[void]$menu.Items.Add("-")

$startServer = $menu.Items.Add((L '\u542f\u52a8 SSH \u8f85\u52a9\u670d\u52a1'))
$startServer.Add_Click({ Start-TerminalAiServer })

$stopServer = $menu.Items.Add((L '\u505c\u6b62 SSH \u8f85\u52a9\u670d\u52a1'))
$stopServer.Add_Click({ Stop-TerminalAiServer })

[void]$menu.Items.Add("-")

$exit = $menu.Items.Add((L '\u9000\u51fa'))
$exit.Add_Click({
    Stop-TerminalAiServer
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.Text = L '\u7ec8\u7aef AI \u52a9\u624b'
$notify.ContextMenuStrip = $menu
$notify.Visible = $true
$notify.Add_DoubleClick({ Show-TerminalAiPanel })

[System.Windows.Forms.Application]::Run()
