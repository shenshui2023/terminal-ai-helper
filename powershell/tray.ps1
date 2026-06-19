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
        [System.Windows.Forms.MessageBox]::Show("Server is already running.", "terminal-ai-helper")
        return
    }
    $root = Split-Path -Parent (Split-Path -Parent $ProfileScript)
    $script:TaihServerProcess = Start-Process -FilePath "node" `
        -ArgumentList @("$root\bin\taih.js", "serve", "--port", "$ServerPort") `
        -WindowStyle Hidden `
        -PassThru
    [System.Windows.Forms.MessageBox]::Show("Server started on 127.0.0.1:$ServerPort", "terminal-ai-helper")
}

function Stop-TerminalAiServer {
    if ($script:TaihServerProcess -and -not $script:TaihServerProcess.HasExited) {
        Stop-Process -Id $script:TaihServerProcess.Id -Force
        [System.Windows.Forms.MessageBox]::Show("Server stopped.", "terminal-ai-helper")
    }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$openPanel = $menu.Items.Add("Open manager panel")
$openPanel.Add_Click({ Show-TerminalAiPanel })

$explainClipboard = $menu.Items.Add("Explain clipboard")
$explainClipboard.Add_Click({ Invoke-TerminalAiClipboard -Mode explain -Window })

$fixClipboard = $menu.Items.Add("Diagnose clipboard")
$fixClipboard.Add_Click({ Invoke-TerminalAiClipboard -Mode fix -Window })

[void]$menu.Items.Add("-")

$startServer = $menu.Items.Add("Start SSH helper server")
$startServer.Add_Click({ Start-TerminalAiServer })

$stopServer = $menu.Items.Add("Stop SSH helper server")
$stopServer.Add_Click({ Stop-TerminalAiServer })

[void]$menu.Items.Add("-")

$exit = $menu.Items.Add("Exit")
$exit.Add_Click({
    Stop-TerminalAiServer
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.Text = "terminal-ai-helper"
$notify.ContextMenuStrip = $menu
$notify.Visible = $true
$notify.Add_DoubleClick({ Show-TerminalAiPanel })

[System.Windows.Forms.Application]::Run()
