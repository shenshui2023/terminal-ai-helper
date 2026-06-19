param(
    [string]$InputFile = "",
    [string]$Mode = "explain",
    [int]$AnchorX = -1,
    [int]$AnchorY = -1,
    [int]$AnchorW = -1,
    [int]$AnchorH = -1
)

$ErrorActionPreference = "Stop"
$script:TaihRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:TaihCli = Join-Path $script:TaihRoot "bin\taih.js"
$script:TaihSettingsPath = Join-Path $env:USERPROFILE ".terminal-ai-helper\panel-settings.json"
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

function Move-PanelNearTerminal {
    param($Form)
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $width = [Math]::Min(620, [Math]::Max(460, [int]($screen.Width * 0.30)))
    $height = if ($AnchorH -gt 300) { [Math]::Min($AnchorH, $screen.Height) } else { [Math]::Min(820, [int]($screen.Height * 0.82)) }
    $x = if ($AnchorX -ge 0) { $AnchorX - $width - 8 } else { $screen.Left + 16 }
    if ($x -lt $screen.Left) {
        $x = if ($AnchorX -ge 0) { $AnchorX + 8 } else { $screen.Left + 16 }
    }
    if (($x + $width) -gt $screen.Right) { $x = $screen.Right - $width - 8 }
    $y = if ($AnchorY -ge 0) { $AnchorY } else { $screen.Top + 24 }
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

function Start-PanelRequest {
    param($ModeBox, $StyleBox, $CommandBox, $RulesBox, $OutputBox, $StatusLabel, $RunButton)

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

    $modeValue = [string]$ModeBox.SelectedItem
    if (-not $modeValue) { $modeValue = "explain" }
    $styleValue = [string]$StyleBox.SelectedItem
    if (-not $styleValue) { $styleValue = "brief" }
    $rules = [string]$RulesBox.Text
    $rulesFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($rulesFile, $rules, [System.Text.Encoding]::UTF8)

    Save-Settings -Style $styleValue -Rules $rules

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $args = @($script:TaihCli, $modeValue, "--stream", "--no-cache", "--style", $styleValue, "--instructions-file", $rulesFile, "--", $text)
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
            $state.OutputBox.Text = (L '\u8bf7\u6c42\u5931\u8d25\uff1a') + "`r`n" + $errorText
        } else {
            $state.StatusLabel.Text = (L '\u5b8c\u6210\uff0c\u7528\u65f6 ') + $seconds + (L ' \u79d2')
        }
        Remove-Item -LiteralPath $state.StdoutFile, $state.StderrFile, $state.RulesFile -Force -ErrorAction SilentlyContinue
        try { $state.Process.Dispose() } catch {}
        $script:TaihProcess = $null
        $script:TaihState = $null
    })
    $timer.Start()
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
[void]$modeBox.Items.Add("explain")
[void]$modeBox.Items.Add("fix")
[void]$modeBox.Items.Add("complete")
$modeBox.SelectedItem = $Mode
if (-not $modeBox.SelectedItem) { $modeBox.SelectedIndex = 0 }
$modeBox.Dock = "Fill"

$styleBox = New-Object System.Windows.Forms.ComboBox
$styleBox.DropDownStyle = "DropDownList"
[void]$styleBox.Items.Add("brief")
[void]$styleBox.Items.Add("standard")
[void]$styleBox.Items.Add("examples")
[void]$styleBox.Items.Add("custom")
$styleBox.SelectedItem = [string]$settings.style
if (-not $styleBox.SelectedItem) { $styleBox.SelectedIndex = 0 }
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
$rulesBox.Text = if ($settings.rules) { [string]$settings.rules } else { L '\u9ed8\u8ba4\uff1a\u4e0d\u8d85\u8fc7 8 \u884c\uff1b\u5148\u8bf4\u4f5c\u7528\uff0c\u518d\u7ed9\u793a\u4f8b\uff1b\u6709\u98ce\u9669\u5fc5\u987b\u63d0\u9192\u3002' }

$output = New-Object System.Windows.Forms.RichTextBox
$output.Dock = "Fill"
$output.ReadOnly = $true
$output.BackColor = [System.Drawing.Color]::Black
$output.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$output.BorderStyle = "FixedSingle"
$output.Font = New-Object System.Drawing.Font("Consolas", 10)
$output.WordWrap = $true
$output.ScrollBars = "Vertical"

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
[void]$root.Controls.Add($output, 0, 3)
[void]$root.Controls.Add($buttons, 0, 4)
[void]$form.Controls.Add($root)

$run.Add_Click({ Start-PanelRequest -ModeBox $modeBox -StyleBox $styleBox -CommandBox $commandBox -RulesBox $rulesBox -OutputBox $output -StatusLabel $status -RunButton $run })
$commandBox.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; Start-PanelRequest -ModeBox $modeBox -StyleBox $styleBox -CommandBox $commandBox -RulesBox $rulesBox -OutputBox $output -StatusLabel $status -RunButton $run } })
$clip.Add_Click({
    $text = Get-Clipboard -Raw
    if ($text) { $commandBox.Text = $text }
})
$copy.Add_Click({ Set-Clipboard -Value $output.Text; $status.Text = L '\u5df2\u590d\u5236' })
$clear.Add_Click({ $output.Clear(); $status.Text = L '\u5df2\u6e05\u7a7a' })
$close.Add_Click({ $form.Close() })

Move-PanelNearTerminal -Form $form
[void]$form.Show()
if ($commandBox.Text.Trim()) {
    Start-PanelRequest -ModeBox $modeBox -StyleBox $styleBox -CommandBox $commandBox -RulesBox $rulesBox -OutputBox $output -StatusLabel $status -RunButton $run
}
[System.Windows.Forms.Application]::Run($form)
