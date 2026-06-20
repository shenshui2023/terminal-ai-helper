param(
    [switch]$SkipApi
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$profilePath = Join-Path $root "powershell\taih-profile.ps1"
$panelPath = Join-Path $root "powershell\panel.ps1"
$trayInstallPath = Join-Path $root "powershell\install-tray-startup.ps1"

Write-Host "test: parsing PowerShell profile"
$parseErrors = $null
foreach ($path in @($profilePath, $panelPath, $trayInstallPath)) {
    $parseErrors = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $path -Raw), [ref]$parseErrors) | Out-Null
    if ($parseErrors) {
        $parseErrors | Format-List *
        throw "PowerShell parse failed: $path"
    }
}

Write-Host "test: loading profile"
. $profilePath

Add-Type -AssemblyName System.Windows.Forms

Write-Host "test: hotkeys and aliases are registered"
$boundKeys = @(Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Function -eq "CustomAction" } | ForEach-Object { $_.Key })
foreach ($key in @("Alt+/", "Alt+?", "Alt+C", "Alt+F", "Ctrl+Spacebar")) {
    if ($boundKeys -notcontains $key) {
        throw "missing hotkey: $key"
    }
}
foreach ($aliasName in @("taih-current", "taih-popup", "taih-panel", "taih-clip", "taih-fix", "taih-keys")) {
    if (-not (Get-Alias $aliasName -ErrorAction SilentlyContinue)) {
        throw "missing alias: $aliasName"
    }
}

Write-Host "test: local completion candidates are available"
$localCompletions = @(Get-TerminalAiLocalCompletions -Prefix "git st")
if (-not ($localCompletions | Where-Object { $_ -like "git status*" })) {
    throw "missing local git status completion"
}

Write-Host "test: panel launcher is non-blocking"
$env:TAIH_TEST_NO_PANEL_START = "1"
try {
    $script:TaihLastPanelArgs = $null
    Show-TerminalAiPanel -InitialText "git status" -Mode explain
    if (-not $script:TaihLastPanelArgs -or ($script:TaihLastPanelArgs -notcontains "-File") -or ($script:TaihLastPanelArgs -notcontains $panelPath)) {
        throw "panel launcher did not prepare independent panel process arguments"
    }
    if (($script:TaihLastPanelArgs -notcontains "-PanelId") -or ($script:TaihLastPanelArgs -notcontains "-AnchorHandle")) {
        throw "panel launcher did not prepare reuse/follow arguments"
    }
} finally {
    Remove-Item Env:\TAIH_TEST_NO_PANEL_START -ErrorAction SilentlyContinue
}

function New-TestControls {
    param([string]$Text)
    $form = New-Object System.Windows.Forms.Form
    $form.ShowInTaskbar = $false
    $form.Opacity = 0
    $mode = New-Object System.Windows.Forms.ComboBox
    [void]$mode.Items.Add("explain")
    $mode.SelectedIndex = 0
    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $Text
    $out = New-Object System.Windows.Forms.RichTextBox
    $status = New-Object System.Windows.Forms.Label
    $progress = New-Object System.Windows.Forms.ProgressBar
    $history = New-Object System.Windows.Forms.ListBox
    $run = New-Object System.Windows.Forms.Button
    $clip = New-Object System.Windows.Forms.Button
    [void]$form.Controls.Add($out)
    [void]$form.Controls.Add($status)
    $form.Show()
    return [pscustomobject]@{
        Form = $form
        Mode = $mode
        Box = $box
        Out = $out
        Status = $status
        Progress = $progress
        History = $history
        Run = $run
        Clip = $clip
    }
}

Write-Host "test: empty input does not throw or call API"
$empty = New-TestControls ""
try {
    Invoke-TerminalAiPanelRequest -ModeBox $empty.Mode -InputBox $empty.Box -OutputBox $empty.Out -StatusLabel $empty.Status -ProgressBar $empty.Progress -HistoryBox $empty.History -RunButton $empty.Run -ClipButton $empty.Clip
    [System.Windows.Forms.Application]::DoEvents()
    if ($empty.Status.Text -eq "" -or $empty.Out.Text -eq "") {
        throw "empty input did not update status/output"
    }
} finally {
    $empty.Form.Close()
}

if (-not $SkipApi) {
    Write-Host "test: async panel request completes"
    $controls = New-TestControls "ps"
    try {
        Invoke-TerminalAiPanelRequest -ModeBox $controls.Mode -InputBox $controls.Box -OutputBox $controls.Out -StatusLabel $controls.Status -ProgressBar $controls.Progress -HistoryBox $controls.History -RunButton $controls.Run -ClipButton $controls.Clip
        $deadline = (Get-Date).AddSeconds(75)
        while ((Get-Date) -lt $deadline -and $script:TaihPanelProcess) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:TaihPanelProcess) {
            try { $script:TaihPanelProcess.Kill() } catch {}
            try { $script:TaihPanelProcess.Dispose() } catch {}
            $script:TaihPanelProcess = $null
            throw "async panel request timed out"
        }
        $donePrefix = L '\u5b8c\u6210'
        if ($controls.Status.Text -notlike ($donePrefix + "*") -or $controls.Out.Text.Trim().Length -eq 0) {
            $preview = $controls.Out.Text
            if ($preview.Length -gt 800) { $preview = $preview.Substring(0, 800) }
            throw ("async panel request failed: status=" + $controls.Status.Text + " outputLength=" + $controls.Out.Text.Length + "`n" + $preview)
        }
    } finally {
        $controls.Form.Close()
    }
}

Write-Host "test: panel tests passed"
