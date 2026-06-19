$script:TaihRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:TaihCli = Join-Path $script:TaihRoot "bin\taih.js"
$script:TaihHistoryItems = New-Object System.Collections.ArrayList

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

function Invoke-TerminalAiNode {
    param([string[]]$Arguments)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "node"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true
    $allArgs = @($script:TaihCli) + $Arguments
    $psi.Arguments = ($allArgs | ForEach-Object { Q $_ }) -join " "

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        $message = ($stderr + $stdout).Trim()
        if (-not $message) { $message = "node exited with code $($process.ExitCode)" }
        throw $message
    }

    return $stdout
}

function Get-TerminalAiContext {
    $buffer = ""
    $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)

    $selectionStart = 0
    $selectionLength = 0
    try {
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    } catch {
        $selectionLength = 0
    }

    if ($selectionLength -gt 0) {
        return $buffer.Substring($selectionStart, $selectionLength)
    }

    $beforeCursor = if ($cursor -gt 0) { $buffer.Substring(0, $cursor) } else { "" }
    $lineBreak = $beforeCursor.LastIndexOf("`n")
    $currentLine = if ($lineBreak -ge 0) { $beforeCursor.Substring($lineBreak + 1) } else { $beforeCursor }
    if (-not $currentLine.Trim()) { $currentLine = $buffer }
    return $currentLine
}

function Invoke-TerminalAiJson {
    param(
        [ValidateSet("explain", "complete", "fix")]
        [string]$Mode,
        [string]$Text
    )
    $env:TAIH_SHELL = "PowerShell $($PSVersionTable.PSVersion)"
    $json = Invoke-TerminalAiNode -Arguments @($Mode, "--json", "--", $Text)
    return ($json | ConvertFrom-Json)
}

function Invoke-TerminalAiText {
    param(
        [ValidateSet("explain", "complete", "fix")]
        [string]$Mode,
        [string]$Text,
        [switch]$Stream,
        [switch]$NoCache
    )
    $env:TAIH_SHELL = "PowerShell $($PSVersionTable.PSVersion)"
    $args = @($Mode)
    if ($Stream) { $args += "--stream" }
    if ($NoCache) { $args += "--no-cache" }
    $args += @("--", $Text)
    return (Invoke-TerminalAiNode -Arguments $args)
}

function Add-TerminalAiHistory {
    param([string]$Mode, [string]$Text, [string]$Output)
    $preview = ($Text -replace '\s+', ' ').Trim()
    if ($preview.Length -gt 80) { $preview = $preview.Substring(0, 80) + "..." }
    $item = [pscustomobject]@{
        Mode = $Mode
        Text = $Text
        Output = $Output
        Preview = "[$Mode] $preview"
        At = Get-Date
    }
    [void]$script:TaihHistoryItems.Insert(0, $item)
    while ($script:TaihHistoryItems.Count -gt 50) {
        $script:TaihHistoryItems.RemoveAt($script:TaihHistoryItems.Count - 1)
    }
}

function Move-TerminalAiFormRight {
    param($Form)
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $width = [Math]::Min(680, [Math]::Max(560, [int]($screen.Width * 0.36)))
    $height = [Math]::Min(840, [Math]::Max(560, [int]($screen.Height * 0.84)))
    $x = $screen.Right - $width - 12
    $y = $screen.Top + 24
    $Form.Size = New-Object System.Drawing.Size($width, $height)
    $Form.Location = New-Object System.Drawing.Point($x, $y)
}

function Invoke-TerminalAiPanelRequest {
    param($ModeBox, $InputBox, $OutputBox, $StatusLabel, $ProgressBar, $HistoryBox)

    $mode = [string]$ModeBox.SelectedItem
    if (-not $mode) { $mode = "explain" }
    $text = $InputBox.Text
    if (-not $text.Trim()) {
        $StatusLabel.Text = L '\u8f93\u5165\u4e3a\u7a7a'
        return
    }

    $StatusLabel.Text = L '\u6b63\u5728\u8bf7\u6c42 AI...'
    $OutputBox.Text = (L '\u6b63\u5728\u751f\u6210\uff0c\u8bf7\u7a0d\u5019...') + "`r`n`r`n" + $text
    $ProgressBar.Visible = $true
    $ProgressBar.MarqueeAnimationSpeed = 30
    [System.Windows.Forms.Application]::DoEvents()

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($mode -eq "complete") {
            $result = Invoke-TerminalAiJson -Mode complete -Text $text
            if ($result.completion) {
                $OutputBox.Text = "$($result.completion)`r`n`r`n$($result.summary)"
            } else {
                $OutputBox.Text = L '\u6ca1\u6709\u53ef\u76f4\u63a5\u63d2\u5165\u7684\u8865\u5168\u5efa\u8bae\u3002'
            }
        } else {
            $resultText = Invoke-TerminalAiText -Mode $mode -Text $text -Stream -NoCache
            $OutputBox.Text = $resultText
        }
        $timer.Stop()
        $StatusLabel.Text = (L '\u5b8c\u6210\uff0c\u7528\u65f6 ') + [Math]::Round($timer.Elapsed.TotalSeconds, 1) + (L ' \u79d2')
        Add-TerminalAiHistory -Mode $mode -Text $text -Output $OutputBox.Text
        $HistoryBox.Items.Clear()
        foreach ($h in $script:TaihHistoryItems) { [void]$HistoryBox.Items.Add($h.Preview) }
    } catch {
        $timer.Stop()
        $StatusLabel.Text = L '\u8bf7\u6c42\u5931\u8d25'
        $OutputBox.Text = (L '\u8bf7\u6c42\u5931\u8d25\uff1a') + "`r`n" + $_.Exception.Message
    } finally {
        $ProgressBar.MarqueeAnimationSpeed = 0
        $ProgressBar.Visible = $false
        $OutputBox.Focus()
    }
}

function Show-TerminalAiPanel {
    param([string]$InitialText = "")

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $bg = [System.Drawing.Color]::FromArgb(18, 22, 28)
    $panelBg = [System.Drawing.Color]::FromArgb(28, 34, 43)
    $surface = [System.Drawing.Color]::FromArgb(13, 17, 23)
    $surface2 = [System.Drawing.Color]::FromArgb(22, 27, 34)
    $fg = [System.Drawing.Color]::FromArgb(230, 237, 243)
    $muted = [System.Drawing.Color]::FromArgb(139, 148, 158)
    $accent = [System.Drawing.Color]::FromArgb(47, 129, 247)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = L '\u7ec8\u7aef AI \u52a9\u624b'
    $form.StartPosition = "Manual"
    $form.MinimumSize = New-Object System.Drawing.Size(560, 480)
    $form.BackColor = $bg
    $form.ForeColor = $fg
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        if ($_.KeyCode -eq "Escape") { $form.Close() }
    })

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = "Fill"
    $root.ColumnCount = 1
    $root.RowCount = 4
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 76)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 76)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Fill"
    $header.BackColor = $panelBg

    $title = New-Object System.Windows.Forms.Label
    $title.Text = L '\u7ec8\u7aef AI \u52a9\u624b'
    $title.Dock = "Top"
    $title.Height = 34
    $title.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 0)
    $title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $fg

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = L '\u53ef\u6eda\u52a8\u3001\u53ef\u9009\u62e9\u3001\u53ef\u590d\u5236\u3002Esc \u6216\u53f3\u4e0a\u89d2 X \u5173\u95ed\u7a97\u53e3\u3002'
    $hint.Dock = "Fill"
    $hint.Padding = New-Object System.Windows.Forms.Padding(16, 0, 16, 0)
    $hint.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $hint.ForeColor = $muted

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Dock = "Bottom"
    $progress.Height = 4
    $progress.Style = "Marquee"
    $progress.Visible = $false
    $progress.MarqueeAnimationSpeed = 0

    [void]$header.Controls.Add($hint)
    [void]$header.Controls.Add($title)
    [void]$header.Controls.Add($progress)

    $inputPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $inputPanel.Dock = "Fill"
    $inputPanel.BackColor = $bg
    $inputPanel.ColumnCount = 4
    $inputPanel.RowCount = 1
    $inputPanel.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 8)
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 94)))
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 104)))

    $mode = New-Object System.Windows.Forms.ComboBox
    $mode.DropDownStyle = "DropDownList"
    [void]$mode.Items.Add("explain")
    [void]$mode.Items.Add("fix")
    [void]$mode.Items.Add("complete")
    $mode.SelectedIndex = 0
    $mode.Dock = "Fill"

    $commandBox = New-Object System.Windows.Forms.TextBox
    $commandBox.Dock = "Fill"
    $commandBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $commandBox.BackColor = $surface2
    $commandBox.ForeColor = $fg
    $commandBox.BorderStyle = "FixedSingle"
    $commandBox.Text = $InitialText

    $run = New-Object System.Windows.Forms.Button
    $run.Text = L '\u6267\u884c'
    $run.Dock = "Fill"
    $run.BackColor = $accent
    $run.ForeColor = [System.Drawing.Color]::White
    $run.FlatStyle = "Flat"

    $clip = New-Object System.Windows.Forms.Button
    $clip.Text = L '\u8bfb\u526a\u8d34\u677f'
    $clip.Dock = "Fill"
    $clip.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 52)
    $clip.ForeColor = $fg
    $clip.FlatStyle = "Flat"

    [void]$inputPanel.Controls.Add($mode, 0, 0)
    [void]$inputPanel.Controls.Add($commandBox, 1, 0)
    [void]$inputPanel.Controls.Add($run, 2, 0)
    [void]$inputPanel.Controls.Add($clip, 3, 0)

    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = "Fill"
    $split.Orientation = "Vertical"
    $split.SplitterDistance = 180
    $split.BackColor = $bg

    $history = New-Object System.Windows.Forms.ListBox
    $history.Dock = "Fill"
    $history.BackColor = $surface
    $history.ForeColor = $muted
    $history.BorderStyle = "FixedSingle"
    $history.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $output = New-Object System.Windows.Forms.RichTextBox
    $output.Multiline = $true
    $output.ReadOnly = $true
    $output.ScrollBars = "Both"
    $output.WordWrap = $true
    $output.Dock = "Fill"
    $output.BorderStyle = "FixedSingle"
    $output.BackColor = $surface
    $output.ForeColor = $fg
    $output.SelectionBackColor = $accent
    $output.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10.5)
    $output.ShortcutsEnabled = $true
    $output.DetectUrls = $true
    $output.HideSelection = $false

    foreach ($h in $script:TaihHistoryItems) { [void]$history.Items.Add($h.Preview) }

    [void]$split.Panel1.Controls.Add($history)
    [void]$split.Panel2.Controls.Add($output)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = "Fill"
    $buttons.FlowDirection = "RightToLeft"
    $buttons.Padding = New-Object System.Windows.Forms.Padding(10)
    $buttons.BackColor = $panelBg

    function New-PanelButton([string]$Text) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text
        $b.Width = 88
        $b.Height = 30
        $b.FlatStyle = "Flat"
        $b.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 52)
        $b.ForeColor = $fg
        return $b
    }

    $close = New-PanelButton (L '\u5173\u95ed')
    $copy = New-PanelButton (L '\u590d\u5236')
    $clear = New-PanelButton (L '\u6e05\u7a7a')
    $cache = New-PanelButton (L '\u6e05\u7f13\u5b58')
    $help = New-PanelButton (L '\u5e2e\u52a9')
    $status = New-Object System.Windows.Forms.Label
    $status.Text = L '\u5c31\u7eea'
    $status.AutoSize = $true
    $status.Padding = New-Object System.Windows.Forms.Padding(0, 7, 14, 0)
    $status.ForeColor = $muted

    [void]$buttons.Controls.Add($close)
    [void]$buttons.Controls.Add($copy)
    [void]$buttons.Controls.Add($clear)
    [void]$buttons.Controls.Add($cache)
    [void]$buttons.Controls.Add($help)
    [void]$buttons.Controls.Add($status)

    [void]$root.Controls.Add($header, 0, 0)
    [void]$root.Controls.Add($inputPanel, 0, 1)
    [void]$root.Controls.Add($split, 0, 2)
    [void]$root.Controls.Add($buttons, 0, 3)
    [void]$form.Controls.Add($root)

    $run.Add_Click({ Invoke-TerminalAiPanelRequest -ModeBox $mode -InputBox $commandBox -OutputBox $output -StatusLabel $status -ProgressBar $progress -HistoryBox $history })
    $commandBox.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; Invoke-TerminalAiPanelRequest -ModeBox $mode -InputBox $commandBox -OutputBox $output -StatusLabel $status -ProgressBar $progress -HistoryBox $history } })
    $clip.Add_Click({
        $clipText = Get-Clipboard -Raw
        if (-not $clipText -or -not $clipText.Trim()) {
            $status.Text = L '\u526a\u8d34\u677f\u4e3a\u7a7a'
            $output.Text = L '\u526a\u8d34\u677f\u4e3a\u7a7a\uff0c\u8bf7\u5148\u590d\u5236\u547d\u4ee4\u6216\u5728\u8f93\u5165\u6846\u624b\u52a8\u8f93\u5165\u3002'
            return
        }
        $commandBox.Text = $clipText
        Invoke-TerminalAiPanelRequest -ModeBox $mode -InputBox $commandBox -OutputBox $output -StatusLabel $status -ProgressBar $progress -HistoryBox $history
    })
    $close.Add_Click({ $form.Close() })
    $copy.Add_Click({ Set-Clipboard -Value $output.Text; $status.Text = L '\u5df2\u590d\u5236' })
    $clear.Add_Click({ $output.Clear(); $status.Text = L '\u5df2\u6e05\u7a7a' })
    $cache.Add_Click({
        try { Invoke-TerminalAiNode -Arguments @("cache", "clear") | Out-Null; $status.Text = L '\u7f13\u5b58\u5df2\u6e05\u7406' }
        catch { $status.Text = L '\u7f13\u5b58\u6e05\u7406\u5931\u8d25' }
    })
    $help.Add_Click({
        $output.Text = (L '\u7ec8\u7aef AI \u52a9\u624b\u5feb\u901f\u8bf4\u660e') + @"

Alt+/        $(L '\u5728\u7ec8\u7aef\u91cc\u76f4\u63a5\u89e3\u91ca\u5f53\u524d\u547d\u4ee4')
Alt+?        $(L '\u6253\u5f00\u7ba1\u7406\u9762\u677f')
Ctrl+Space   $(L '\u8865\u5168\u5f53\u524d\u547d\u4ee4\u5e76\u63d2\u5165')
Alt+Shift+F  $(L '\u8bca\u65ad\u5f53\u524d\u547d\u4ee4')

SSH:
1. node bin/taih.js serve --port 17888
2. ssh -R 17888:127.0.0.1:17888 <user>@<host>
3. source /path/to/terminal-ai-helper/remote/taih-bash.sh
"@
    })
    $history.Add_SelectedIndexChanged({
        $idx = $history.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:TaihHistoryItems.Count) {
            $item = $script:TaihHistoryItems[$idx]
            $commandBox.Text = $item.Text
            $output.Text = $item.Output
            $status.Text = (L '\u5386\u53f2\uff1a') + $item.Mode
        }
    })

    Move-TerminalAiFormRight -Form $form
    [void]$form.ShowDialog()
}

function Invoke-TerminalAiHelper {
    param(
        [ValidateSet("explain", "complete", "fix")]
        [string]$Mode = "explain",
        [string]$Text,
        [switch]$Window,
        [switch]$Copy
    )
    if (-not $Text) { $Text = Get-TerminalAiContext }
    if (-not $Text.Trim()) { Write-Host (L '\u5f53\u524d\u547d\u4ee4\u4e3a\u7a7a\u3002') -ForegroundColor Yellow; return }

    if ($Window) {
        Show-TerminalAiPanel -InitialText $Text
        return
    }

    Write-Host ""
    Write-Host (L 'AI \u6b63\u5728\u5de5\u4f5c...') -ForegroundColor DarkGray
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-TerminalAiText -Mode $Mode -Text $Text
        $timer.Stop()
        if ($Copy) { Set-Clipboard -Value $result }
        Write-Host $result -ForegroundColor Cyan
        Write-Host ((L '\u5b8c\u6210\uff0c\u7528\u65f6 ') + [Math]::Round($timer.Elapsed.TotalSeconds, 1) + (L ' \u79d2')) -ForegroundColor DarkGray
    } catch {
        Write-Host ((L '\u8bf7\u6c42\u5931\u8d25\uff1a') + $_.Exception.Message) -ForegroundColor Red
    }
}

function Show-TerminalAiUsage { Invoke-TerminalAiHelper -Mode explain -Text (Get-TerminalAiContext); [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
function Show-TerminalAiUsageWindow { Show-TerminalAiPanel -InitialText (Get-TerminalAiContext); [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
function Show-TerminalAiFixWindow { $text = Get-TerminalAiContext; Show-TerminalAiPanel -InitialText $text; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
function Complete-TerminalAiCommand {
    $text = Get-TerminalAiContext
    if (-not $text.Trim()) { return }
    Write-Host ""
    Write-Host (L 'AI \u6b63\u5728\u8865\u5168...') -ForegroundColor DarkGray
    try {
        $result = Invoke-TerminalAiJson -Mode complete -Text $text
        if ($result.completion) {
            Write-Host ((L '\u8865\u5168\uff1a') + $result.completion) -ForegroundColor Green
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result.completion)
        } else {
            Write-Host (L '\u6ca1\u6709\u53ef\u76f4\u63a5\u63d2\u5165\u7684\u8865\u5168\u3002') -ForegroundColor Yellow
        }
    } catch {
        Write-Host ((L '\u8865\u5168\u5931\u8d25\uff1a') + $_.Exception.Message) -ForegroundColor Red
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}
function Copy-TerminalAiCompletion {
    $text = Get-TerminalAiContext
    if (-not $text.Trim()) { return }
    try {
        $result = Invoke-TerminalAiJson -Mode complete -Text $text
        if ($result.completion) {
            Set-Clipboard -Value $result.completion
            Write-Host ((L '\u8865\u5168\u5df2\u590d\u5236\uff1a') + $result.completion) -ForegroundColor Green
        }
    } catch {
        Write-Host ((L '\u590d\u5236\u8865\u5168\u5931\u8d25\uff1a') + $_.Exception.Message) -ForegroundColor Red
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}
function Invoke-TerminalAiClipboard {
    param(
        [ValidateSet("explain", "complete", "fix")]
        [string]$Mode = "explain",
        [switch]$Window,
        [switch]$Copy
    )
    $text = Get-Clipboard -Raw
    if (-not $text.Trim()) { Write-Host (L '\u526a\u8d34\u677f\u4e3a\u7a7a\u3002') -ForegroundColor Yellow; return }
    Invoke-TerminalAiHelper -Mode $Mode -Text $text -Window:$Window -Copy:$Copy
}

Set-PSReadLineKeyHandler -Chord "Alt+/" -ScriptBlock { Show-TerminalAiUsage }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+/" -ScriptBlock { Show-TerminalAiUsageWindow }
Set-PSReadLineKeyHandler -Chord "Alt+?" -ScriptBlock { Show-TerminalAiPanel }
Set-PSReadLineKeyHandler -Chord "Ctrl+Spacebar" -ScriptBlock { Complete-TerminalAiCommand }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+C" -ScriptBlock { Copy-TerminalAiCompletion }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+F" -ScriptBlock { Show-TerminalAiFixWindow }

Set-Alias taih-current Show-TerminalAiUsage -Force
Set-Alias taih-popup Show-TerminalAiUsageWindow -Force
Set-Alias taih-panel Show-TerminalAiPanel -Force
Set-Alias taih-clip Invoke-TerminalAiClipboard -Force
Set-Alias taih-fix Show-TerminalAiFixWindow -Force

Write-Host (L '\u7ec8\u7aef AI \u52a9\u624b\u5df2\u52a0\u8f7d\uff1a') -ForegroundColor DarkCyan
Write-Host (L '  Alt+/        \u89e3\u91ca\u9009\u4e2d\u6587\u672c\u6216\u5f53\u524d\u547d\u4ee4')
Write-Host (L '  Alt+?        \u6253\u5f00\u7ba1\u7406\u9762\u677f')
Write-Host (L '  Ctrl+Space   \u63d2\u5165 AI \u8865\u5168')
Write-Host (L '  Alt+Shift+C  \u590d\u5236 AI \u8865\u5168')
Write-Host (L '  Alt+Shift+F  \u8bca\u65ad\u9009\u4e2d\u6587\u672c\u6216\u5f53\u524d\u547d\u4ee4')
