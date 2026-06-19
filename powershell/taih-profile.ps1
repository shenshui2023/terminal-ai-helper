$script:TaihRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:TaihCli = Join-Path $script:TaihRoot "bin\taih.js"
$script:TaihPanel = $null
$script:TaihOutput = $null
$script:TaihInput = $null
$script:TaihHistory = $null
$script:TaihStatus = $null
$script:TaihProgress = $null
$script:TaihMode = $null
$script:TaihHistoryItems = New-Object System.Collections.ArrayList

function ConvertTo-TerminalAiProcessArgument {
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
    $psi.Arguments = ($allArgs | ForEach-Object { ConvertTo-TerminalAiProcessArgument $_ }) -join " "

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
        return [pscustomobject]@{ Text = $buffer.Substring($selectionStart, $selectionLength); Source = "selection" }
    }

    $beforeCursor = if ($cursor -gt 0) { $buffer.Substring(0, $cursor) } else { "" }
    $lineBreak = $beforeCursor.LastIndexOf("`n")
    $currentLine = if ($lineBreak -ge 0) { $beforeCursor.Substring($lineBreak + 1) } else { $beforeCursor }
    if (-not $currentLine.Trim()) { $currentLine = $buffer }
    return [pscustomobject]@{ Text = $currentLine; Source = "current-command" }
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
        [switch]$NoCache
    )
    $env:TAIH_SHELL = "PowerShell $($PSVersionTable.PSVersion)"
    $args = @($Mode)
    if ($NoCache) { $args += "--no-cache" }
    $args += @("--", $Text)
    return (Invoke-TerminalAiNode -Arguments $args)
}

function Invoke-TerminalAiStreamToPanel {
    param(
        [ValidateSet("explain", "fix")]
        [string]$Mode,
        [string]$Text
    )

    $env:TAIH_SHELL = "PowerShell $($PSVersionTable.PSVersion)"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "node"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true
    $args = @($script:TaihCli, $Mode, "--stream", "--no-cache", "--", $Text)
    $psi.Arguments = ($args | ForEach-Object { ConvertTo-TerminalAiProcessArgument $_ }) -join " "

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true
    [void]$process.Start()
    $buffer = New-Object System.Text.StringBuilder
    $errorBuffer = New-Object System.Text.StringBuilder

    $outHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.Data) {
            [void]$buffer.AppendLine($eventArgs.Data)
        }
    }
    $errHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.Data) {
            [void]$errorBuffer.AppendLine($eventArgs.Data)
        }
    }
    $process.add_OutputDataReceived($outHandler)
    $process.add_ErrorDataReceived($errHandler)
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    $lastLength = -1
    while (-not $process.HasExited) {
        $current = $buffer.ToString()
        if ($current.Length -ne $lastLength) {
            $lastLength = $current.Length
            $script:TaihOutput.Text = $current
            $script:TaihOutput.SelectionStart = $script:TaihOutput.TextLength
            $script:TaihOutput.ScrollToCaret()
        }
        Start-Sleep -Milliseconds 80
        [System.Windows.Forms.Application]::DoEvents()
    }

    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        $err = $errorBuffer.ToString()
        if ($err) { throw $err }
        throw "stream process exited with code $($process.ExitCode)"
    }

    $final = $buffer.ToString()
    $script:TaihOutput.Text = $final
    return $final
}

function Add-TerminalAiNativeMethods {
    if ("TerminalAi.Native" -as [type]) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace TerminalAi {
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static class Native {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  }
}
"@
}

function Move-TerminalAiPanelNearTerminal {
    if (-not $script:TaihPanel) { return }
    Add-TerminalAiNativeMethods
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $width = [Math]::Min(620, [Math]::Max(520, [int]($screen.Width * 0.34)))
    $height = [Math]::Min(820, [Math]::Max(560, [int]($screen.Height * 0.82)))
    $x = $screen.Right - $width - 12
    $y = $screen.Top + 24

    try {
        $rect = New-Object TerminalAi.RECT
        $hwnd = [TerminalAi.Native]::GetForegroundWindow()
        if ([TerminalAi.Native]::GetWindowRect($hwnd, [ref]$rect)) {
            if (($rect.Right + $width + 12) -lt $screen.Right) {
                $x = $rect.Right + 10
                $y = [Math]::Max($screen.Top + 12, $rect.Top)
                $height = [Math]::Min($height, [Math]::Max(480, $rect.Bottom - $rect.Top))
            }
        }
    } catch {
        # Keep default right-side placement.
    }

    $script:TaihPanel.Size = New-Object System.Drawing.Size($width, $height)
    $script:TaihPanel.Location = New-Object System.Drawing.Point($x, $y)
}

function Add-TerminalAiHistory {
    param([string]$Mode, [string]$Text, [string]$Output)
    $preview = ($Text -replace '\s+', ' ').Trim()
    if ($preview.Length -gt 80) { $preview = $preview.Substring(0, 80) + "..." }
    $item = [pscustomobject]@{ Mode = $Mode; Text = $Text; Output = $Output; Preview = "[$Mode] $preview"; At = Get-Date }
    [void]$script:TaihHistoryItems.Insert(0, $item)
    while ($script:TaihHistoryItems.Count -gt 50) { $script:TaihHistoryItems.RemoveAt($script:TaihHistoryItems.Count - 1) }
    if ($script:TaihHistory) {
        $script:TaihHistory.Items.Clear()
        foreach ($h in $script:TaihHistoryItems) { [void]$script:TaihHistory.Items.Add($h.Preview) }
    }
}

function Initialize-TerminalAiPanel {
    if ($script:TaihPanel -and -not $script:TaihPanel.IsDisposed) { return }

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
    $form.Text = "terminal-ai-helper"
    $form.StartPosition = "Manual"
    $form.Size = New-Object System.Drawing.Size(600, 760)
    $form.MinimumSize = New-Object System.Drawing.Size(520, 460)
    $form.TopMost = $false
    $form.BackColor = $bg
    $form.ForeColor = $fg
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        if ($_.KeyCode -eq "Escape") { $script:TaihPanel.Hide() }
        if ($_.Control -and $_.KeyCode -eq "L") { $script:TaihOutput.Clear() }
    })
    $form.Add_FormClosing({
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $_.Cancel = $true
            $script:TaihPanel.Hide()
        }
    })

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = "Fill"
    $root.ColumnCount = 1
    $root.RowCount = 4
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 76)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 74)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Fill"
    $header.BackColor = $panelBg

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "terminal-ai-helper"
    $title.AutoSize = $false
    $title.Dock = "Top"
    $title.Height = 34
    $title.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 0)
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $fg

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Docked side panel. Scroll, select, copy. Esc hides."
    $hint.AutoSize = $false
    $hint.Dock = "Fill"
    $hint.Padding = New-Object System.Windows.Forms.Padding(16, 0, 16, 0)
    $hint.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $hint.ForeColor = $muted

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Dock = "Bottom"
    $progress.Height = 4
    $progress.Style = "Marquee"
    $progress.MarqueeAnimationSpeed = 0
    $progress.Visible = $false
    [void]$header.Controls.Add($hint)
    [void]$header.Controls.Add($title)
    [void]$header.Controls.Add($progress)

    $inputPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $inputPanel.Dock = "Fill"
    $inputPanel.BackColor = $bg
    $inputPanel.ColumnCount = 4
    $inputPanel.RowCount = 1
    $inputPanel.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 8)
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 96)))
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
    [void]$inputPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))

    $mode = New-Object System.Windows.Forms.ComboBox
    $mode.DropDownStyle = "DropDownList"
    [void]$mode.Items.Add("explain")
    [void]$mode.Items.Add("fix")
    [void]$mode.Items.Add("complete")
    $mode.SelectedIndex = 0
    $mode.Dock = "Fill"

    $input = New-Object System.Windows.Forms.TextBox
    $input.Dock = "Fill"
    $input.Font = New-Object System.Drawing.Font("Consolas", 10)
    $input.BackColor = $surface2
    $input.ForeColor = $fg
    $input.BorderStyle = "FixedSingle"

    $run = New-Object System.Windows.Forms.Button
    $run.Text = "Run"
    $run.Dock = "Fill"
    $run.BackColor = $accent
    $run.ForeColor = [System.Drawing.Color]::White
    $run.FlatStyle = "Flat"

    $clip = New-Object System.Windows.Forms.Button
    $clip.Text = "Clip"
    $clip.Dock = "Fill"
    $clip.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 52)
    $clip.ForeColor = $fg
    $clip.FlatStyle = "Flat"

    [void]$inputPanel.Controls.Add($mode, 0, 0)
    [void]$inputPanel.Controls.Add($input, 1, 0)
    [void]$inputPanel.Controls.Add($run, 2, 0)
    [void]$inputPanel.Controls.Add($clip, 3, 0)

    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = "Fill"
    $split.Orientation = "Vertical"
    $split.SplitterDistance = 170
    $split.BackColor = $bg

    $history = New-Object System.Windows.Forms.ListBox
    $history.Dock = "Fill"
    $history.BackColor = $surface
    $history.ForeColor = $muted
    $history.BorderStyle = "None"
    $history.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $output = New-Object System.Windows.Forms.RichTextBox
    $output.Multiline = $true
    $output.ReadOnly = $true
    $output.ScrollBars = "Both"
    $output.WordWrap = $true
    $output.Dock = "Fill"
    $output.BorderStyle = "None"
    $output.BackColor = $surface
    $output.ForeColor = $fg
    $output.SelectionBackColor = $accent
    $output.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10.5)
    $output.ShortcutsEnabled = $true
    $output.DetectUrls = $true

    [void]$split.Panel1.Controls.Add($history)
    [void]$split.Panel2.Controls.Add($output)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = "Fill"
    $buttons.FlowDirection = "RightToLeft"
    $buttons.Padding = New-Object System.Windows.Forms.Padding(10)
    $buttons.BackColor = $panelBg

    function New-TaihButton([string]$Text) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text
        $b.Width = 86
        $b.Height = 30
        $b.FlatStyle = "Flat"
        $b.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 52)
        $b.ForeColor = $fg
        return $b
    }

    $hide = New-TaihButton "Hide"
    $copy = New-TaihButton "Copy"
    $clear = New-TaihButton "Clear"
    $cache = New-TaihButton "Cache-"
    $settings = New-TaihButton "Help"
    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Ready"
    $status.AutoSize = $true
    $status.Padding = New-Object System.Windows.Forms.Padding(0, 7, 14, 0)
    $status.ForeColor = $muted

    [void]$buttons.Controls.Add($hide)
    [void]$buttons.Controls.Add($copy)
    [void]$buttons.Controls.Add($clear)
    [void]$buttons.Controls.Add($cache)
    [void]$buttons.Controls.Add($settings)
    [void]$buttons.Controls.Add($status)

    [void]$root.Controls.Add($header, 0, 0)
    [void]$root.Controls.Add($inputPanel, 0, 1)
    [void]$root.Controls.Add($split, 0, 2)
    [void]$root.Controls.Add($buttons, 0, 3)
    [void]$form.Controls.Add($root)

    $script:TaihPanel = $form
    $script:TaihOutput = $output
    $script:TaihInput = $input
    $script:TaihHistory = $history
    $script:TaihStatus = $status
    $script:TaihProgress = $progress
    $script:TaihMode = $mode

    $run.Add_Click({ Invoke-TerminalAiPanelRun })
    $input.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; Invoke-TerminalAiPanelRun } })
    $clip.Add_Click({ $script:TaihInput.Text = Get-Clipboard -Raw; Invoke-TerminalAiPanelRun })
    $hide.Add_Click({ $script:TaihPanel.Hide() })
    $copy.Add_Click({ Set-Clipboard -Value $script:TaihOutput.Text; $script:TaihStatus.Text = "Copied" })
    $clear.Add_Click({ $script:TaihOutput.Clear(); $script:TaihStatus.Text = "Cleared" })
    $cache.Add_Click({
        try { Invoke-TerminalAiNode -Arguments @("cache", "clear") | Out-Null; $script:TaihStatus.Text = "Cache cleared" }
        catch { $script:TaihStatus.Text = "Cache clear failed" }
    })
    $settings.Add_Click({
        $script:TaihOutput.Text = @"
terminal-ai-helper quick help

Alt+/        print help in terminal
Alt+Shift+/  open or update this side panel
Ctrl+Space   insert completion
Alt+Shift+C  copy completion
Alt+Shift+F  diagnose command

SSH:
1. Local: node bin/taih.js serve --port 17888
2. SSH:   ssh -R 17888:127.0.0.1:17888 <user>@<host>
3. Remote: source /path/to/terminal-ai-helper/remote/taih-bash.sh
"@
    })
    $history.Add_SelectedIndexChanged({
        $idx = $script:TaihHistory.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:TaihHistoryItems.Count) {
            $item = $script:TaihHistoryItems[$idx]
            $script:TaihInput.Text = $item.Text
            $script:TaihOutput.Text = $item.Output
            $script:TaihStatus.Text = "History: $($item.Mode)"
        }
    })

    Move-TerminalAiPanelNearTerminal
}

function Update-TerminalAiPanel {
    param(
        [string]$Title = "terminal-ai-helper",
        [string]$Text,
        [string]$Status = "Ready",
        [string]$InputText = "",
        [string]$Mode = "explain",
        [switch]$Busy,
        [switch]$Activate
    )
    Initialize-TerminalAiPanel
    $script:TaihPanel.Text = $Title
    if ($InputText) { $script:TaihInput.Text = $InputText }
    if ($Mode -and $script:TaihMode.Items.Contains($Mode)) { $script:TaihMode.SelectedItem = $Mode }
    $script:TaihOutput.Text = $Text
    $script:TaihOutput.SelectionStart = 0
    $script:TaihOutput.ScrollToCaret()
    $script:TaihStatus.Text = $Status
    $script:TaihProgress.Visible = [bool]$Busy
    $script:TaihProgress.MarqueeAnimationSpeed = if ($Busy) { 30 } else { 0 }
    if (-not $script:TaihPanel.Visible) { $script:TaihPanel.Show() }
    if ($Activate) { [void]$script:TaihPanel.Activate(); $script:TaihOutput.Focus() }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-TerminalAiPanelRun {
    Initialize-TerminalAiPanel
    $mode = [string]$script:TaihMode.SelectedItem
    if (-not $mode) { $mode = "explain" }
    $text = $script:TaihInput.Text
    if (-not $text.Trim()) { $script:TaihStatus.Text = "Empty input"; return }
    Invoke-TerminalAiHelper -Mode $mode -Text $text -Window
}

function Invoke-TerminalAiHelper {
    param(
        [ValidateSet("explain", "complete", "fix")]
        [string]$Mode = "explain",
        [string]$Text,
        [switch]$Window,
        [switch]$Copy,
        [switch]$NoCache
    )
    if (-not $Text) { $Text = (Get-TerminalAiContext).Text }
    if (-not $Text.Trim()) { Write-Host "`nCurrent command is empty." -ForegroundColor Yellow; return }

    $preview = if ($Text.Length -gt 600) { $Text.Substring(0, 600) + "..." } else { $Text }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    if ($Window) {
        Update-TerminalAiPanel -Title "terminal-ai-helper: $Mode" -Text "Working...`r`n`r`n$preview" -Status "Calling API..." -InputText $Text -Mode $Mode -Busy -Activate
    } else {
        Write-Host ""; Write-Host "AI is working... ($Mode)" -ForegroundColor DarkGray
    }

    try {
        if ($Window -and ($Mode -eq "explain" -or $Mode -eq "fix")) {
            $result = Invoke-TerminalAiStreamToPanel -Mode $Mode -Text $Text
        } else {
            $result = Invoke-TerminalAiText -Mode $Mode -Text $Text -NoCache:$NoCache
        }
    }
    catch {
        $timer.Stop()
        $msg = "Request failed after $([math]::Round($timer.Elapsed.TotalSeconds, 1))s.`r`n`r`n$($_.Exception.Message)"
        if ($Window) { Update-TerminalAiPanel -Title "terminal-ai-helper: $Mode failed" -Text $msg -Status "Failed" -InputText $Text -Mode $Mode -Activate }
        else { Write-Host "AI request failed: $($_.Exception.Message)" -ForegroundColor Red }
        return
    }

    $timer.Stop()
    if ($Copy) { Set-Clipboard -Value $result; Write-Host "AI result copied to clipboard." -ForegroundColor Green }
    Add-TerminalAiHistory -Mode $Mode -Text $Text -Output $result
    if ($Window) {
        Update-TerminalAiPanel -Title "terminal-ai-helper: $Mode" -Text $result -Status "Done in $([math]::Round($timer.Elapsed.TotalSeconds, 1))s" -InputText $Text -Mode $Mode -Activate
    } else {
        Write-Host $result -ForegroundColor Cyan
        Write-Host "Done in $([math]::Round($timer.Elapsed.TotalSeconds, 1))s" -ForegroundColor DarkGray
    }
}

function Show-TerminalAiUsage { Invoke-TerminalAiHelper -Mode explain -Text (Get-TerminalAiContext).Text; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
function Show-TerminalAiUsageWindow { Invoke-TerminalAiHelper -Mode explain -Text (Get-TerminalAiContext).Text -Window; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
function Show-TerminalAiFixWindow { Invoke-TerminalAiHelper -Mode fix -Text (Get-TerminalAiContext).Text -Window; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
function Show-TerminalAiPanel { Initialize-TerminalAiPanel; Move-TerminalAiPanelNearTerminal; if (-not $script:TaihPanel.Visible) { $script:TaihPanel.Show() }; [void]$script:TaihPanel.Activate() }

function Complete-TerminalAiCommand {
    $ctx = Get-TerminalAiContext
    if (-not $ctx.Text.Trim()) { return }
    Write-Host ""; Write-Host "AI completion is working..." -ForegroundColor DarkGray
    try {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-TerminalAiJson -Mode complete -Text $ctx.Text
        $timer.Stop()
        if ($result.completion) {
            Write-Host "AI completion: $($result.completion)" -ForegroundColor Green
            Write-Host "Summary: $($result.summary)" -ForegroundColor DarkGray
            Write-Host "Done in $([math]::Round($timer.Elapsed.TotalSeconds, 1))s" -ForegroundColor DarkGray
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result.completion)
        } else { Write-Host "AI returned no direct completion." -ForegroundColor Yellow }
    } catch { Write-Host "AI completion failed: $($_.Exception.Message)" -ForegroundColor Red }
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

function Copy-TerminalAiCompletion {
    $ctx = Get-TerminalAiContext
    if (-not $ctx.Text.Trim()) { return }
    try {
        Write-Host "`nAI completion is working..." -ForegroundColor DarkGray
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-TerminalAiJson -Mode complete -Text $ctx.Text
        $timer.Stop()
        if ($result.completion) {
            Set-Clipboard -Value $result.completion
            Write-Host "`nAI completion copied: $($result.completion)" -ForegroundColor Green
            Write-Host "Done in $([math]::Round($timer.Elapsed.TotalSeconds, 1))s" -ForegroundColor DarkGray
        } else { Write-Host "`nAI returned no direct completion." -ForegroundColor Yellow }
    } catch { Write-Host "`nAI completion failed: $($_.Exception.Message)" -ForegroundColor Red }
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
    if (-not $text.Trim()) { Write-Host "Clipboard is empty." -ForegroundColor Yellow; return }
    Invoke-TerminalAiHelper -Mode $Mode -Text $text -Window:$Window -Copy:$Copy
}

Set-PSReadLineKeyHandler -Chord "Alt+/" -ScriptBlock { Show-TerminalAiUsage }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+/" -ScriptBlock { Show-TerminalAiUsageWindow }
Set-PSReadLineKeyHandler -Chord "Ctrl+Spacebar" -ScriptBlock { Complete-TerminalAiCommand }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+C" -ScriptBlock { Copy-TerminalAiCompletion }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+F" -ScriptBlock { Show-TerminalAiFixWindow }

Set-Alias taih-current Show-TerminalAiUsage
Set-Alias taih-popup Show-TerminalAiUsageWindow
Set-Alias taih-panel Show-TerminalAiPanel
Set-Alias taih-clip Invoke-TerminalAiClipboard
Set-Alias taih-fix Show-TerminalAiFixWindow

Write-Host "terminal-ai-helper loaded:" -ForegroundColor DarkCyan
Write-Host "  Alt+/        explain selected text or current command"
Write-Host "  Alt+Shift+/  open or update the docked manager panel"
Write-Host "  Ctrl+Space   insert AI completion"
Write-Host "  Alt+Shift+C  copy AI completion"
Write-Host "  Alt+Shift+F  diagnose selected text or current command"
