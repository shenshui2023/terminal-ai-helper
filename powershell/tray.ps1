param(
    [string]$ProfileScript = "E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1",
    [int]$ServerPort = 17888
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. $ProfileScript

$script:TaihServerProcess = $null
$script:TaihHotKeyForm = $null

Add-Type -ReferencedAssemblies "System.Windows.Forms", "System.Drawing" -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class TaihHotKeyEventArgs : EventArgs {
    public int Id { get; private set; }
    public TaihHotKeyEventArgs(int id) { Id = id; }
}

public class TaihHotKeyForm : Form {
    private const int WM_HOTKEY = 0x0312;
    public event EventHandler<TaihHotKeyEventArgs> HotKeyPressed;
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && HotKeyPressed != null) {
            HotKeyPressed(this, new TaihHotKeyEventArgs(m.WParam.ToInt32()));
        }
        base.WndProc(ref m);
    }
}

public static class TaihHotKeyNative {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@

$MOD_ALT = 0x0001
$MOD_CONTROL = 0x0002
$VK_OEM_2 = 0xBF
$VK_F = 0x46
$HOTKEY_EXPLAIN_SELECTION = 101
$HOTKEY_FIX_SELECTION = 102

function Show-TerminalAiTrayTip {
    param([string]$Text)
    if ($notify) {
        $notify.BalloonTipTitle = L '\u7ec8\u7aef AI \u52a9\u624b'
        $notify.BalloonTipText = $Text
        $notify.ShowBalloonTip(2500)
    }
}

function Get-TerminalAiClipboardText {
    try {
        return (Get-Clipboard -Raw -ErrorAction Stop)
    } catch {
        return ""
    }
}

function Invoke-TerminalAiSelectedTextPanel {
    param(
        [ValidateSet("explain", "fix")]
        [string]$Mode = "explain"
    )

    [System.Windows.Forms.SendKeys]::SendWait("^c")
    Start-Sleep -Milliseconds 220
    $text = Get-TerminalAiClipboardText
    if (-not $text -or -not $text.Trim()) {
        Show-TerminalAiTrayTip (L '\u672a\u8bfb\u5230\u9009\u4e2d\u6587\u672c\u3002\u8bf7\u5148\u5728\u7ec8\u7aef\u91cc\u7528\u9f20\u6807\u9009\u4e2d\u547d\u4ee4\u6216\u62a5\u9519\u3002')
        return
    }
    Show-TerminalAiPanel -InitialText $text -Mode $Mode
}

function Register-TerminalAiGlobalHotKeys {
    $script:TaihHotKeyForm = New-Object TaihHotKeyForm
    $script:TaihHotKeyForm.ShowInTaskbar = $false
    $script:TaihHotKeyForm.FormBorderStyle = "None"
    $script:TaihHotKeyForm.Size = New-Object System.Drawing.Size(1, 1)
    $script:TaihHotKeyForm.Opacity = 0
    $script:TaihHotKeyForm.StartPosition = "Manual"
    $script:TaihHotKeyForm.Location = New-Object System.Drawing.Point(-32000, -32000)
    $script:TaihHotKeyForm.Add_Shown({ $script:TaihHotKeyForm.Hide() })
    $script:TaihHotKeyForm.add_HotKeyPressed({
        param($sender, $eventArgs)
        switch ($eventArgs.Id) {
            $HOTKEY_EXPLAIN_SELECTION { Invoke-TerminalAiSelectedTextPanel -Mode explain }
            $HOTKEY_FIX_SELECTION { Invoke-TerminalAiSelectedTextPanel -Mode fix }
        }
    })
    [void]$script:TaihHotKeyForm.CreateControl()
    [void][TaihHotKeyNative]::RegisterHotKey($script:TaihHotKeyForm.Handle, $HOTKEY_EXPLAIN_SELECTION, ($MOD_CONTROL -bor $MOD_ALT), $VK_OEM_2)
    [void][TaihHotKeyNative]::RegisterHotKey($script:TaihHotKeyForm.Handle, $HOTKEY_FIX_SELECTION, ($MOD_CONTROL -bor $MOD_ALT), $VK_F)
}

function Unregister-TerminalAiGlobalHotKeys {
    if ($script:TaihHotKeyForm) {
        [void][TaihHotKeyNative]::UnregisterHotKey($script:TaihHotKeyForm.Handle, $HOTKEY_EXPLAIN_SELECTION)
        [void][TaihHotKeyNative]::UnregisterHotKey($script:TaihHotKeyForm.Handle, $HOTKEY_FIX_SELECTION)
        try { $script:TaihHotKeyForm.Close() } catch {}
        try { $script:TaihHotKeyForm.Dispose() } catch {}
        $script:TaihHotKeyForm = $null
    }
}

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

$explainSelection = $menu.Items.Add((L '\u89e3\u91ca\u5f53\u524d\u9009\u4e2d\u6587\u672c\uff08Ctrl+Alt+/\uff09'))
$explainSelection.Add_Click({ Invoke-TerminalAiSelectedTextPanel -Mode explain })

$fixSelection = $menu.Items.Add((L '\u8bca\u65ad\u5f53\u524d\u9009\u4e2d\u6587\u672c\uff08Ctrl+Alt+F\uff09'))
$fixSelection.Add_Click({ Invoke-TerminalAiSelectedTextPanel -Mode fix })

[void]$menu.Items.Add("-")

$startServer = $menu.Items.Add((L '\u542f\u52a8 SSH \u8f85\u52a9\u670d\u52a1'))
$startServer.Add_Click({ Start-TerminalAiServer })

$stopServer = $menu.Items.Add((L '\u505c\u6b62 SSH \u8f85\u52a9\u670d\u52a1'))
$stopServer.Add_Click({ Stop-TerminalAiServer })

[void]$menu.Items.Add("-")

$exit = $menu.Items.Add((L '\u9000\u51fa'))
$exit.Add_Click({
    Unregister-TerminalAiGlobalHotKeys
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

Register-TerminalAiGlobalHotKeys
Show-TerminalAiTrayTip (L 'Ctrl+Alt+/ \u89e3\u91ca\u9009\u4e2d\u6587\u672c\uff1bCtrl+Alt+F \u8bca\u65ad\u9009\u4e2d\u6587\u672c\u3002SSH \u7ec8\u7aef\u4e2d\u5148\u7528\u9f20\u6807\u9009\u4e2d\u5185\u5bb9\u3002')

[System.Windows.Forms.Application]::Run($script:TaihHotKeyForm)
