param(
    [string]$InputFile = "",
    [string]$Mode = "explain",
    [string]$PanelId = "",
    [long]$AnchorHandle = 0,
    [int]$AnchorX = -1,
    [int]$AnchorY = -1,
    [int]$AnchorW = -1,
    [int]$AnchorH = -1
)

$ErrorActionPreference = "Stop"
$script:TaihRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:TaihCli = Join-Path $script:TaihRoot "bin\taih.js"
$script:TaihSettingsPath = Join-Path $env:USERPROFILE ".terminal-ai-helper\panel-settings.json"
$script:TaihPanelDir = Join-Path $env:USERPROFILE ".terminal-ai-helper\panels"
$script:TaihPanelId = if ($PanelId) { $PanelId } else { "pid-$PID" }
$script:TaihCommandFile = Join-Path $script:TaihPanelDir "$script:TaihPanelId.command.json"
$script:TaihPidFile = Join-Path $script:TaihPanelDir "$script:TaihPanelId.pid"
$script:TaihLastCommandStamp = [DateTime]::MinValue
$script:TaihProcess = $null
$script:TaihTimer = $null
$script:TaihState = $null

function L {
    param([string]$Text)
    $evaluator = {
        param($Match)
        [string][char]([Convert]::ToInt32($Match.Groups[1].Value, 16))
    }
    return [regex]::Replace($Text, '\\u([0-9a-fA-F]{4})', [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

function Q {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Ensure-Win32 {
    if ("TaihPanelWin32" -as [type]) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TaihPanelWin32 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
}

function Get-AnchorRect {
    Ensure-Win32
    if ($AnchorHandle -gt 0) {
        $hwnd = [IntPtr]$AnchorHandle
        if ([TaihPanelWin32]::IsWindow($hwnd)) {
            $rect = New-Object TaihPanelWin32+RECT
            if ([TaihPanelWin32]::GetWindowRect($hwnd, [ref]$rect)) {
                return [pscustomobject]@{
                    X = $rect.Left
                    Y = $rect.Top
                    W = $rect.Right - $rect.Left
                    H = $rect.Bottom - $rect.Top
                }
            }
        }
    }
    return [pscustomobject]@{ X = $AnchorX; Y = $AnchorY; W = $AnchorW; H = $AnchorH }
}

function Test-AnchorAlive {
    Ensure-Win32
    if ($AnchorHandle -le 0) { return $true }
    return [TaihPanelWin32]::IsWindow([IntPtr]$AnchorHandle)
}

function To-ModeValue {
    param([string]$Value)
    if ($Value -match '^explain') { return "explain" }
    if ($Value -match '^fix') { return "fix" }
    if ($Value -match '^complete') { return "complete" }
    return $Value
}

function To-StyleValue {
    param([string]$Value)
    if ($Value -match '^brief') { return "brief" }
    if ($Value -match '^standard') { return "standard" }
    if ($Value -match '^examples') { return "examples" }
    if ($Value -match '^custom') { return "custom" }
    return $Value
}

function Select-ComboByPrefix {
    param($Combo, [string]$Prefix)
    for ($i = 0; $i -lt $Combo.Items.Count; $i++) {
        if ([string]$Combo.Items[$i] -match "^$Prefix") {
            $Combo.SelectedIndex = $i
            return
        }
    }
}

function Read-InitialText {
    if ($InputFile -and (Test-Path -LiteralPath $InputFile)) {
        try {
            $text = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)
            Remove-Item -LiteralPath $InputFile -Force -ErrorAction SilentlyContinue
            return $text
        } catch {}
    }
    return ""
}

function Read-Settings {
    try {
        if (Test-Path -LiteralPath $script:TaihSettingsPath) {
            return (Get-Content -LiteralPath $script:TaihSettingsPath -Raw | ConvertFrom-Json)
        }
    } catch {}
    return [pscustomobject]@{ style = "brief"; rules = "" }
}

function Save-Settings {
    param([string]$Style, [string]$Rules)
    $dir = Split-Path -Parent $script:TaihSettingsPath
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [pscustomobject]@{ style = $Style; rules = $Rules } |
        ConvertTo-Json |
        Set-Content -LiteralPath $script:TaihSettingsPath -Encoding UTF8
}

function Read-HistoryItems {
    try {
        $json = & node $script:TaihCli history --json
        if (-not $json) { return @() }
        return @($json | ConvertFrom-Json)
    } catch {
        return @()
    }
}

function Refresh-HistoryList {
    param($HistoryBox)
    if (-not $HistoryBox) { return }
    $script:TaihHistoryItems = @(Read-HistoryItems)
    $HistoryBox.Items.Clear()
    foreach ($item in $script:TaihHistoryItems) {
        $text = [string]$item.text
        $text = ($text -replace '\s+', ' ').Trim()
        if ($text.Length -gt 54) { $text = $text.Substring(0, 54) + "..." }
        $prefix = if ($item.cacheHit) { "[cache]" } else { "[ai]" }
        [void]$HistoryBox.Items.Add("$prefix [$($item.mode)] $text")
    }
}

function Move-PanelNearTerminal {
    param($Form)
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $anchor = Get-AnchorRect
    $width = [Math]::Min(620, [Math]::Max(460, [int]($screen.Width * 0.30)))
    $height = if ($anchor.H -gt 300) { [Math]::Min($anchor.H, $screen.Height) } else { [Math]::Min(820, [int]($screen.Height * 0.82)) }
    $x = if ($anchor.X -ge 0) { $anchor.X + $anchor.W } else { $screen.Right - $width - 16 }
    if (($x + $width) -gt $screen.Right) {
        $x = if ($anchor.X -ge 0) { $anchor.X - $width } else { $screen.Right - $width - 16 }
    }
    if ($x -lt $screen.Left) { $x = $screen.Left + 8 }
    if (($x + $width) -gt $screen.Right) { $x = $screen.Right - $width - 8 }
    $y = if ($anchor.Y -ge 0) { $anchor.Y } else { $screen.Top + 24 }
    if ($y -lt $screen.Top) { $y = $screen.Top }
    if (($y + $height) -gt $screen.Bottom) { $height = $screen.Bottom - $y - 8 }
    $Form.Size = New-Object System.Drawing.Size($width, $height)
    $Form.Location = New-Object System.Drawing.Point($x, $y)
}

function Append-Output {
    param($Box, [string]$Text)
    if (-not $Text) { return }
    $Box.AppendText($Text)
    $Box.SelectionStart = $Box.TextLength
    $Box.ScrollToCaret()
}

function Format-PanelOutput {
    param([string]$Text)
    if (-not $Text) { return "" }

    $lines = ($Text -replace "`r`n|`r", "`n").Split("`n") | ForEach-Object { $_.TrimEnd() }
    $result = New-Object System.Collections.Generic.List[string]
    $blankCount = 0
    $inCodeBlock = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^```') { $inCodeBlock = -not $inCodeBlock }

        if (-not $inCodeBlock -and $trimmed -match '^(常规用法|用法|示例|风险提醒|风险|下一步|修复步骤|原因|作用|注意):?$') {
            if ($result.Count -gt 0 -and $result[$result.Count - 1].Trim()) {
                $result.Add("")
            }
            $line = $trimmed.TrimEnd(":") + ":"
        } elseif (-not $inCodeBlock -and $trimmed -match '^[-*]\s+') {
            $line = "  " + $trimmed
        } elseif (-not $inCodeBlock -and $trimmed -match '^\d+\.\s+') {
            $line = "  " + $trimmed
        }

        if (-not $line.Trim()) {
            $blankCount++
            if ($blankCount -le 1) { $result.Add("") }
            continue
        }

        $blankCount = 0
        $result.Add($line)
    }

    return (($result -join "`r`n").Trim() + "`r`n")
}

function Stop-RunningRequest {
    if ($script:TaihTimer) {
        try { $script:TaihTimer.Stop(); $script:TaihTimer.Dispose() } catch {}
        $script:TaihTimer = $null
    }
    if ($script:TaihProcess -and -not $script:TaihProcess.HasExited) {
        try { $script:TaihProcess.Kill() } catch {}
    }
    if ($script:TaihState) {
        Remove-Item -LiteralPath $script:TaihState.StdoutFile, $script:TaihState.StderrFile, $script:TaihState.RulesFile -Force -ErrorAction SilentlyContinue
    }
    $script:TaihProcess = $null
    $script:TaihState = $null
}

function Apply-PanelCommand {
    param($ModeBox, $CommandBox, $OutputBox, $StatusLabel, $RunButton, $StyleBox, $RulesBox, $HistoryBox)
    try {
        if (-not (Test-Path -LiteralPath $script:TaihCommandFile)) { return }
        $file = Get-Item -LiteralPath $script:TaihCommandFile
        if ($file.LastWriteTimeUtc -le $script:TaihLastCommandStamp) { return }
        $script:TaihLastCommandStamp = $file.LastWriteTimeUtc
        $payload = Get-Content -LiteralPath $script:TaihCommandFile -Raw | ConvertFrom-Json
        $text = ""
        if ($payload.inputFile -and (Test-Path -LiteralPath $payload.inputFile)) {
            $text = [System.IO.File]::ReadAllText([string]$payload.inputFile, [System.Text.Encoding]::UTF8)
            Remove-Item -LiteralPath ([string]$payload.inputFile) -Force -ErrorAction SilentlyContinue
        }
        if ($script:TaihProcess -and -not $script:TaihProcess.HasExited) {
            Stop-RunningRequest
            $RunButton.Enabled = $true
            $RunButton.Text = L '\u6267\u884c'
            $OutputBox.Clear()
        }
        if ($payload.mode) { Select-ComboByPrefix -Combo $ModeBox -Prefix ([string]$payload.mode) }
        $CommandBox.Text = $text
        $StatusLabel.Text = L '\u5df2\u63a5\u6536\u65b0\u547d\u4ee4'
        $form.Activate()
        [TaihPanelWin32]::SetForegroundWindow($form.Handle) | Out-Null
        if ($text.Trim()) {
            Start-PanelRequest -ModeBox $ModeBox -StyleBox $StyleBox -CommandBox $CommandBox -RulesBox $RulesBox -OutputBox $OutputBox -StatusLabel $StatusLabel -RunButton $RunButton -HistoryBox $HistoryBox
        }
    } catch {
        $StatusLabel.Text = L '\u8bfb\u53d6\u65b0\u547d\u4ee4\u5931\u8d25'
    }
}

function Start-PanelRequest {
    param($ModeBox, $StyleBox, $CommandBox, $RulesBox, $OutputBox, $StatusLabel, $RunButton, $HistoryBox)

    if ($script:TaihProcess -and -not $script:TaihProcess.HasExited) {
        $StatusLabel.Text = L '\u6b63\u5728\u6267\u884c\uff0c\u8bf7\u5148\u7b49\u5f85\u6216\u5173\u95ed\u7a97\u53e3'
        return
    }

    $text = [string]$CommandBox.Text
    if (-not $text.Trim()) {
        $StatusLabel.Text = L '\u8f93\u5165\u4e3a\u7a7a'
        $OutputBox.Text = L '\u8bf7\u8f93\u5165\u547d\u4ee4\uff0c\u6216\u5148\u590d\u5236\u5185\u5bb9\u540e\u70b9\u201c\u8bfb\u526a\u8d34\u677f\u201d\u3002'
        return
    }

    $modeValue = To-ModeValue ([string]$ModeBox.SelectedItem)
    if (-not $modeValue) { $modeValue = "explain" }
    $styleValue = To-StyleValue ([string]$StyleBox.SelectedItem)
    if (-not $styleValue) { $styleValue = "brief" }
    $rules = [string]$RulesBox.Text
    $rulesFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($rulesFile, $rules, [System.Text.Encoding]::UTF8)

    Save-Settings -Style $styleValue -Rules $rules

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $args = @($script:TaihCli, $modeValue, "--stream", "--style", $styleValue, "--instructions-file", $rulesFile, "--", $text)
    $argumentLine = ($args | ForEach-Object { Q $_ }) -join " "

    $OutputBox.Clear()
    $StatusLabel.Text = L '\u6b63\u5728\u751f\u6210...'
    $RunButton.Enabled = $false
    $RunButton.Text = L '\u8fd0\u884c\u4e2d'

    $process = Start-Process -FilePath "node" -ArgumentList $argumentLine -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden -PassThru
    $script:TaihProcess = $process
    $script:TaihState = [pscustomobject]@{
        Process = $process
        StdoutFile = $stdoutFile
        StderrFile = $stderrFile
        RulesFile = $rulesFile
        LastLength = 0
        Started = Get-Date
        OutputBox = $OutputBox
        StatusLabel = $StatusLabel
        RunButton = $RunButton
        HistoryBox = $HistoryBox
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $script:TaihTimer = $timer
    $timer.Add_Tick({
        $state = $script:TaihState
        if (-not $state) { return }
        $currentText = ""
        try {
            if (Test-Path -LiteralPath $state.StdoutFile) {
                $currentText = [System.IO.File]::ReadAllText($state.StdoutFile, [System.Text.Encoding]::UTF8)
            }
        } catch {}
        if ($currentText.Length -gt $state.LastLength) {
            $chunk = $currentText.Substring($state.LastLength)
            $state.LastLength = $currentText.Length
            Append-Output -Box $state.OutputBox -Text $chunk
        }
        if (-not $state.Process.HasExited) { return }

        $script:TaihTimer.Stop()
        $script:TaihTimer.Dispose()
        $script:TaihTimer = $null
        $state.RunButton.Enabled = $true
        $state.RunButton.Text = L '\u6267\u884c'
        $seconds = [Math]::Round(((Get-Date) - $state.Started).TotalSeconds, 1)
        $errorText = ""
        try { if (Test-Path -LiteralPath $state.StderrFile) { $errorText = [System.IO.File]::ReadAllText($state.StderrFile, [System.Text.Encoding]::UTF8) } } catch {}
        if ($errorText.Trim()) {
            $state.StatusLabel.Text = L '\u8bf7\u6c42\u5931\u8d25'
            $state.OutputBox.Text = Format-PanelOutput ((L '\u8bf7\u6c42\u5931\u8d25\uff1a') + "`r`n" + $errorText)
        } else {
            $finalText = ""
            try { if (Test-Path -LiteralPath $state.StdoutFile) { $finalText = [System.IO.File]::ReadAllText($state.StdoutFile, [System.Text.Encoding]::UTF8) } } catch {}
            if ($finalText.Trim()) { $state.OutputBox.Text = Format-PanelOutput $finalText }
            $state.StatusLabel.Text = (L '\u5b8c\u6210\uff0c\u7528\u65f6 ') + $seconds + (L ' \u79d2')
        }
        Refresh-HistoryList -HistoryBox $state.HistoryBox
        Remove-Item -LiteralPath $state.StdoutFile, $state.StderrFile, $state.RulesFile -Force -ErrorAction SilentlyContinue
        try { $state.Process.Dispose() } catch {}
        $script:TaihProcess = $null
        $script:TaihState = $null
    })
    $timer.Start()
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Ensure-Win32
New-Item -ItemType Directory -Path $script:TaihPanelDir -Force | Out-Null
Set-Content -LiteralPath $script:TaihPidFile -Value $PID -Encoding ASCII
if (Test-Path -LiteralPath $script:TaihCommandFile) {
    try { $script:TaihLastCommandStamp = (Get-Item -LiteralPath $script:TaihCommandFile).LastWriteTimeUtc } catch {}
}

$settings = Read-Settings
$bg = [System.Drawing.Color]::FromArgb(12, 12, 12)
$surface = [System.Drawing.Color]::FromArgb(18, 18, 18)
$border = [System.Drawing.Color]::FromArgb(55, 55, 55)
$fg = [System.Drawing.Color]::FromArgb(220, 220, 220)
$muted = [System.Drawing.Color]::FromArgb(150, 150, 150)
$accent = [System.Drawing.Color]::FromArgb(0, 122, 204)

$form = New-Object System.Windows.Forms.Form
$form.Text = L '\u7ec8\u7aef AI \u4fa7\u680f'
$form.StartPosition = "Manual"
$form.BackColor = $bg
$form.ForeColor = $fg
$form.MinimumSize = New-Object System.Drawing.Size(420, 520)
$form.KeyPreview = $true
$form.Add_KeyDown({ if ($_.KeyCode -eq "Escape") { $form.Close() } })
$form.Add_FormClosing({ Stop-RunningRequest })
$form.Add_FormClosed({
    Remove-Item -LiteralPath $script:TaihPidFile, $script:TaihCommandFile -Force -ErrorAction SilentlyContinue
})

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = "Fill"
$root.RowCount = 5
$root.ColumnCount = 1
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 72)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 86)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))

$title = New-Object System.Windows.Forms.Label
$title.Text = L '\u7ec8\u7aef AI \u4fa7\u680f  \u00b7 \u5f53\u524d\u7ec8\u7aef\u53ef\u7ee7\u7eed\u4f7f\u7528'
$title.Dock = "Fill"
$title.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 0)
$title.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $fg

$top = New-Object System.Windows.Forms.TableLayoutPanel
$top.Dock = "Fill"
$top.ColumnCount = 3
$top.RowCount = 2
$top.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
[void]$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
[void]$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
[void]$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$modeBox = New-Object System.Windows.Forms.ComboBox
$modeBox.DropDownStyle = "DropDownList"
[void]$modeBox.Items.Add((L 'explain \uff08\u89e3\u6790\u547d\u4ee4\uff09'))
[void]$modeBox.Items.Add((L 'fix \uff08\u8bca\u65ad\u62a5\u9519\uff09'))
[void]$modeBox.Items.Add((L 'complete \uff08\u8865\u5168\u547d\u4ee4\uff09'))
Select-ComboByPrefix -Combo $modeBox -Prefix $Mode
if ($modeBox.SelectedIndex -lt 0) { $modeBox.SelectedIndex = 0 }
$modeBox.Dock = "Fill"

$styleBox = New-Object System.Windows.Forms.ComboBox
$styleBox.DropDownStyle = "DropDownList"
[void]$styleBox.Items.Add((L 'brief \uff08\u7b80\u6d01\uff09'))
[void]$styleBox.Items.Add((L 'standard \uff08\u6807\u51c6\uff09'))
[void]$styleBox.Items.Add((L 'examples \uff08\u793a\u4f8b\u4f18\u5148\uff09'))
[void]$styleBox.Items.Add((L 'custom \uff08\u6309\u89c4\u5219\uff09'))
Select-ComboByPrefix -Combo $styleBox -Prefix ([string]$settings.style)
if ($styleBox.SelectedIndex -lt 0) { $styleBox.SelectedIndex = 0 }
$styleBox.Dock = "Fill"

$commandBox = New-Object System.Windows.Forms.TextBox
$commandBox.Dock = "Fill"
$commandBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$commandBox.BackColor = $surface
$commandBox.ForeColor = $fg
$commandBox.BorderStyle = "FixedSingle"
$commandBox.Text = Read-InitialText

[void]$top.Controls.Add($modeBox, 0, 0)
[void]$top.Controls.Add($styleBox, 1, 0)
[void]$top.Controls.Add($commandBox, 2, 0)
$top.SetColumnSpan($commandBox, 1)

$rulesBox = New-Object System.Windows.Forms.TextBox
$rulesBox.Multiline = $true
$rulesBox.Dock = "Fill"
$rulesBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$rulesBox.BackColor = $surface
$rulesBox.ForeColor = $muted
$rulesBox.BorderStyle = "FixedSingle"
$rulesBox.Text = if ($settings.rules) { [string]$settings.rules } else { L '\u9ed8\u8ba4\uff1a\u4e0d\u8d85\u8fc7 8 \u884c\uff1b\u6bb5\u843d\u4e4b\u95f4\u7559\u4e00\u4e2a\u7a7a\u884c\uff1b\u5217\u8868\u548c\u793a\u4f8b\u7528\u4e24\u4e2a\u7a7a\u683c\u7f29\u8fdb\uff1b\u5148\u8bf4\u4f5c\u7528\uff0c\u518d\u7ed9\u793a\u4f8b\uff1b\u6709\u98ce\u9669\u5fc5\u987b\u63d0\u9192\u3002' }

$output = New-Object System.Windows.Forms.RichTextBox
$output.Dock = "Fill"
$output.ReadOnly = $true
$output.BackColor = [System.Drawing.Color]::Black
$output.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$output.BorderStyle = "FixedSingle"
$output.Font = New-Object System.Drawing.Font("Consolas", 10)
$output.WordWrap = $true
$output.ScrollBars = "Vertical"

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"
$split.Orientation = "Vertical"
$split.SplitterDistance = 150
$split.BackColor = $bg

$historyBox = New-Object System.Windows.Forms.ListBox
$historyBox.Dock = "Fill"
$historyBox.BackColor = $surface
$historyBox.ForeColor = $muted
$historyBox.BorderStyle = "FixedSingle"
$historyBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
Refresh-HistoryList -HistoryBox $historyBox

[void]$split.Panel1.Controls.Add($historyBox)
[void]$split.Panel2.Controls.Add($output)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.Dock = "Fill"
$buttons.FlowDirection = "RightToLeft"
$buttons.Padding = New-Object System.Windows.Forms.Padding(6)
$buttons.BackColor = $bg

function New-Button([string]$Text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Width = 78
    $b.Height = 28
    $b.FlatStyle = "Flat"
    $b.BackColor = $surface
    $b.ForeColor = $fg
    return $b
}

$close = New-Button (L '\u5173\u95ed')
$copy = New-Button (L '\u590d\u5236')
$clear = New-Button (L '\u6e05\u7a7a')
$clip = New-Button (L '\u8bfb\u526a\u8d34\u677f')
$run = New-Button (L '\u6267\u884c')
$run.BackColor = $accent
$status = New-Object System.Windows.Forms.Label
$status.Text = L '\u5c31\u7eea'
$status.AutoSize = $true
$status.ForeColor = $muted
$status.Padding = New-Object System.Windows.Forms.Padding(0, 6, 12, 0)

[void]$buttons.Controls.Add($close)
[void]$buttons.Controls.Add($copy)
[void]$buttons.Controls.Add($clear)
[void]$buttons.Controls.Add($clip)
[void]$buttons.Controls.Add($run)
[void]$buttons.Controls.Add($status)

[void]$root.Controls.Add($title, 0, 0)
[void]$root.Controls.Add($top, 0, 1)
[void]$root.Controls.Add($rulesBox, 0, 2)
[void]$root.Controls.Add($split, 0, 3)
[void]$root.Controls.Add($buttons, 0, 4)
[void]$form.Controls.Add($root)

$run.Add_Click({ Start-PanelRequest -ModeBox $modeBox -StyleBox $styleBox -CommandBox $commandBox -RulesBox $rulesBox -OutputBox $output -StatusLabel $status -RunButton $run -HistoryBox $historyBox })
$commandBox.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; Start-PanelRequest -ModeBox $modeBox -StyleBox $styleBox -CommandBox $commandBox -RulesBox $rulesBox -OutputBox $output -StatusLabel $status -RunButton $run -HistoryBox $historyBox } })
$historyBox.Add_SelectedIndexChanged({
    $idx = $historyBox.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $script:TaihHistoryItems.Count) {
        $item = $script:TaihHistoryItems[$idx]
        $commandBox.Text = [string]$item.text
        if ($item.mode) { $modeBox.SelectedItem = [string]$item.mode }
        if ($item.output) {
            $output.Text = Format-PanelOutput ([string]$item.output)
            $status.Text = L '\u5df2\u6253\u5f00\u5386\u53f2'
        } else {
            $output.Text = Format-PanelOutput ([string]$item.summary)
            $status.Text = L '\u5386\u53f2\u547d\u4ee4\u5df2\u586b\u5165'
        }
    }
})
$clip.Add_Click({
    $text = Get-Clipboard -Raw
    if ($text) { $commandBox.Text = $text }
})
$copy.Add_Click({ Set-Clipboard -Value $output.Text; $status.Text = L '\u5df2\u590d\u5236' })
$clear.Add_Click({ $output.Clear(); $status.Text = L '\u5df2\u6e05\u7a7a' })
$close.Add_Click({ $form.Close() })

Move-PanelNearTerminal -Form $form
[void]$form.Show()

$followTimer = New-Object System.Windows.Forms.Timer
$followTimer.Interval = 300
$followTimer.Add_Tick({
    if (-not (Test-AnchorAlive)) {
        $form.Close()
        return
    }
    Move-PanelNearTerminal -Form $form
})
$followTimer.Start()
$form.Add_FormClosed({ try { $followTimer.Stop(); $followTimer.Dispose() } catch {} })

$commandTimer = New-Object System.Windows.Forms.Timer
$commandTimer.Interval = 300
$commandTimer.Add_Tick({
    Apply-PanelCommand -ModeBox $modeBox -CommandBox $commandBox -OutputBox $output -StatusLabel $status -RunButton $run -StyleBox $styleBox -RulesBox $rulesBox -HistoryBox $historyBox
})
$commandTimer.Start()
$form.Add_FormClosed({ try { $commandTimer.Stop(); $commandTimer.Dispose() } catch {} })

if ($commandBox.Text.Trim()) {
    Start-PanelRequest -ModeBox $modeBox -StyleBox $styleBox -CommandBox $commandBox -RulesBox $rulesBox -OutputBox $output -StatusLabel $status -RunButton $run -HistoryBox $historyBox
}
[System.Windows.Forms.Application]::Run($form)
