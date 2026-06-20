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

function Get-TerminalAiLineState {
    $buffer = ""
    $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)

    $beforeCursor = if ($cursor -gt 0) { $buffer.Substring(0, $cursor) } else { "" }
    $lineBreak = $beforeCursor.LastIndexOf("`n")
    $lineStart = if ($lineBreak -ge 0) { $lineBreak + 1 } else { 0 }
    $nextBreak = $buffer.IndexOf("`n", $lineStart)
    $lineEnd = if ($nextBreak -ge 0) { $nextBreak } else { $buffer.Length }
    $currentLine = if ($lineEnd -gt $lineStart) { $buffer.Substring($lineStart, $lineEnd - $lineStart) } else { "" }

    return [pscustomobject]@{
        Buffer = $buffer
        Cursor = $cursor
        LineStart = $lineStart
        LineLength = $currentLine.Length
        CurrentLine = $currentLine
    }
}

function Get-TerminalAiLocalCompletions {
    param([string]$Prefix)

    $text = ([string]$Prefix).Trim()
    if (-not $text) { return @() }
    $command = ($text -split '\s+', 2)[0].ToLowerInvariant()
    $items = New-Object System.Collections.Generic.List[string]

    switch ($command) {
        "git" {
            foreach ($item in @(
                "git status -sb",
                "git log --oneline -5",
                "git diff -- <文件路径>",
                "git add <文件路径>",
                "git commit -m `"<说明>`"",
                "git push -u origin <分支名>"
            )) { if ($item.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq "git") { $items.Add($item) } }
        }
        "ssh" {
            foreach ($item in @(
                "ssh <用户名>@<主机> -p <端口>",
                "ssh -i <私钥路径> <用户名>@<主机> -p <端口>",
                "ssh -L <本地端口>:127.0.0.1:<远端端口> <用户名>@<主机>",
                "ssh -R <远端端口>:127.0.0.1:<本地端口> <用户名>@<主机>"
            )) { if ($item.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq "ssh") { $items.Add($item) } }
        }
        "docker" {
            foreach ($item in @(
                "docker ps --format `"table {{.Names}}\t{{.Status}}\t{{.Ports}}`"",
                "docker logs -f <容器名或ID>",
                "docker exec -it <容器名或ID> sh",
                "docker compose up -d",
                "docker compose logs -f <服务名>"
            )) { if ($item.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq "docker") { $items.Add($item) } }
        }
        "npm" {
            foreach ($item in @("npm install", "npm run dev", "npm run build", "npm test", "npm outdated")) { if ($item.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq "npm") { $items.Add($item) } }
        }
        "python" {
            foreach ($item in @("python -m venv .venv", "python -m pip install <包名>", "python -m pytest", "python <脚本.py>")) { if ($item.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq "python") { $items.Add($item) } }
        }
        "java" {
            foreach ($item in @("java -version", "javac <文件.java>", "java -jar <文件.jar>")) { if ($item.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq "java") { $items.Add($item) } }
        }
        "adb" {
            foreach ($item in @("adb devices", "adb shell", "adb logcat", "adb install <应用.apk>", "adb reverse tcp:<端口> tcp:<端口>")) { if ($item.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq "adb") { $items.Add($item) } }
        }
    }

    if ($items.Count -eq 0 -and $text.Length -ge 2) {
        $items.Add("$text --help")
        if ($text -notmatch '\s') { $items.Add("Get-Command $text -Syntax") }
    }

    return @($items | Select-Object -First 6)
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

function Get-TerminalAiControlText {
    param($Control)
    if ($null -eq $Control) { return "" }
    try {
        $value = $Control.Text
        if ($null -eq $value) { return "" }
        return [string]$value
    } catch {
        return ""
    }
}

function Add-TerminalAiOutputText {
    param($OutputBox, [string]$Text)
    if ($null -eq $OutputBox -or $OutputBox.IsDisposed -or -not $Text) { return }
    $append = [System.Action[string]]{
        param($value)
        if ($OutputBox.IsDisposed) { return }
        $OutputBox.AppendText($value)
        $OutputBox.SelectionStart = $OutputBox.TextLength
        $OutputBox.ScrollToCaret()
    }
    if ($OutputBox.InvokeRequired -and $OutputBox.IsHandleCreated) {
        [void]$OutputBox.BeginInvoke($append, [object[]]@($Text))
        return
    }
    $append.Invoke($Text)
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
    param($ModeBox, $InputBox, $OutputBox, $StatusLabel, $ProgressBar, $HistoryBox, $RunButton, $ClipButton)

    $mode = [string]$ModeBox.SelectedItem
    if (-not $mode) { $mode = "explain" }
    $text = Get-TerminalAiControlText $InputBox
    if (-not $text.Trim()) {
        $StatusLabel.Text = L '\u8f93\u5165\u4e3a\u7a7a'
        $OutputBox.Text = L '\u8f93\u5165\u4e3a\u7a7a\uff0c\u8bf7\u5728\u4e0a\u65b9\u8f93\u5165\u547d\u4ee4\uff0c\u6216\u70b9\u51fb\u201c\u8bfb\u526a\u8d34\u677f\u201d\u3002'
        return
    }

    if ($script:TaihPanelProcess -and -not $script:TaihPanelProcess.HasExited) {
        $StatusLabel.Text = L '\u5df2\u6709\u8bf7\u6c42\u5728\u6267\u884c'
        return
    }

    $StatusLabel.Text = L '\u6b63\u5728\u8bf7\u6c42 AI...'
    $OutputBox.Text = (L '\u6b63\u5728\u751f\u6210\uff0c\u8bf7\u7a0d\u5019...') + "`r`n`r`n" + $text
    $ProgressBar.Visible = $true
    $ProgressBar.MarqueeAnimationSpeed = 30
    if ($RunButton) { $RunButton.Enabled = $false; $RunButton.Text = L '\u8fd0\u884c\u4e2d' }
    if ($ClipButton) { $ClipButton.Enabled = $false }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $args = @($mode)
        if ($mode -ne "complete") { $args += @("--stream", "--no-cache") }
        $args += @("--", $text)

        $env:TAIH_SHELL = "PowerShell $($PSVersionTable.PSVersion)"
        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()
        $allArgs = @($script:TaihCli) + $args
        $argumentLine = ($allArgs | ForEach-Object { Q $_ }) -join " "
        $process = Start-Process -FilePath "node" -ArgumentList $argumentLine -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden -PassThru

        $finishTimer = New-Object System.Windows.Forms.Timer
        $script:TaihPanelTimer = $finishTimer
        $script:TaihPanelState = [pscustomobject]@{
            Process = $process
            StdoutFile = $stdoutFile
            StderrFile = $stderrFile
            LastLength = 0
            Stopwatch = $timer
            Mode = $mode
            Text = $text
            OutputBox = $OutputBox
            StatusLabel = $StatusLabel
            ProgressBar = $ProgressBar
            HistoryBox = $HistoryBox
            RunButton = $RunButton
            ClipButton = $ClipButton
        }
        $finishTimer.Interval = 250
        $finishTimer.Add_Tick({
            try {
                $state = $script:TaihPanelState
                if ($null -eq $state) { return }
                $currentText = ""
                try {
                    if (Test-Path -LiteralPath $state.StdoutFile) {
                        $currentText = [System.IO.File]::ReadAllText($state.StdoutFile, [System.Text.Encoding]::UTF8)
                    }
                } catch {
                    $currentText = ""
                }
                if ($currentText.Length -gt $state.LastLength) {
                    $chunk = $currentText.Substring($state.LastLength)
                    $state.LastLength = $currentText.Length
                    Add-TerminalAiOutputText -OutputBox $state.OutputBox -Text $chunk
                }

                if (-not $state.Process.HasExited) { return }

                $script:TaihPanelTimer.Stop()
                $script:TaihPanelTimer.Dispose()
                $state.Stopwatch.Stop()
                $state.ProgressBar.MarqueeAnimationSpeed = 0
                $state.ProgressBar.Visible = $false
                if ($state.RunButton) { $state.RunButton.Enabled = $true; $state.RunButton.Text = L '\u6267\u884c' }
                if ($state.ClipButton) { $state.ClipButton.Enabled = $true }

                $finalText = ""
                $errorText = ""
                try { if (Test-Path -LiteralPath $state.StdoutFile) { $finalText = [System.IO.File]::ReadAllText($state.StdoutFile, [System.Text.Encoding]::UTF8) } } catch {}
                try { if (Test-Path -LiteralPath $state.StderrFile) { $errorText = [System.IO.File]::ReadAllText($state.StderrFile, [System.Text.Encoding]::UTF8) } } catch {}

                if (-not $errorText.Trim() -and $finalText.Trim()) {
                    if ($state.OutputBox.Text -ne $finalText) { $state.OutputBox.Text = $finalText }
                    $state.StatusLabel.Text = (L '\u5b8c\u6210\uff0c\u7528\u65f6 ') + [Math]::Round($state.Stopwatch.Elapsed.TotalSeconds, 1) + (L ' \u79d2')
                    Add-TerminalAiHistory -Mode $state.Mode -Text $state.Text -Output $finalText
                    $state.HistoryBox.Items.Clear()
                    foreach ($h in $script:TaihHistoryItems) { [void]$state.HistoryBox.Items.Add($h.Preview) }
                } else {
                    $message = ($errorText + $finalText).Trim()
                    if (-not $message) { $message = "node did not return output" }
                    $state.StatusLabel.Text = L '\u8bf7\u6c42\u5931\u8d25'
                    $state.OutputBox.Text = (L '\u8bf7\u6c42\u5931\u8d25\uff1a') + "`r`n" + $message
                }

                if ($script:TaihPanelProcess -eq $state.Process) { $script:TaihPanelProcess = $null }
                $script:TaihPanelTimer = $null
                $script:TaihPanelState = $null
                Remove-Item -LiteralPath $state.StdoutFile, $state.StderrFile -Force -ErrorAction SilentlyContinue
                $state.Process.Dispose()
            } catch {
                $state = $script:TaihPanelState
                if ($script:TaihPanelTimer) { $script:TaihPanelTimer.Stop(); $script:TaihPanelTimer.Dispose() }
                if ($state) {
                    $state.StatusLabel.Text = L '\u8bf7\u6c42\u5931\u8d25'
                    $state.OutputBox.Text = (L '\u8bf7\u6c42\u5931\u8d25\uff1a') + "`r`n" + $_.Exception.Message
                    if ($script:TaihPanelProcess -eq $state.Process) { $script:TaihPanelProcess = $null }
                    Remove-Item -LiteralPath $state.StdoutFile, $state.StderrFile -Force -ErrorAction SilentlyContinue
                    try { $state.Process.Dispose() } catch {}
                }
                $script:TaihPanelTimer = $null
                $script:TaihPanelState = $null
            }
        })

        $script:TaihPanelProcess = $process
        $OutputBox.Clear()
        $finishTimer.Start()
    } catch {
        $timer.Stop()
        $StatusLabel.Text = L '\u8bf7\u6c42\u5931\u8d25'
        $OutputBox.Text = (L '\u8bf7\u6c42\u5931\u8d25\uff1a') + "`r`n" + $_.Exception.Message
        $ProgressBar.MarqueeAnimationSpeed = 0
        $ProgressBar.Visible = $false
        if ($RunButton) { $RunButton.Enabled = $true; $RunButton.Text = L '\u6267\u884c' }
        if ($ClipButton) { $ClipButton.Enabled = $true }
    }
}

function Get-TerminalAiLocalCompletions {
    param([string]$Prefix)

    $text = ([string]$Prefix).Trim()
    if (-not $text) { return @() }
    $command = ($text -split '\s+', 2)[0].ToLowerInvariant()
    $items = New-Object System.Collections.Generic.List[string]

    function Add-LocalCandidate([string]$Candidate) {
        if (-not $Candidate) { return }
        if ($Candidate.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq $command) {
            $items.Add($Candidate)
        }
    }

    switch ($command) {
        "git" {
            @(
                "git status -sb",
                "git log --oneline -5",
                "git diff -- <文件路径>",
                "git add <文件路径>",
                "git commit -m `"<说明>`"",
                "git push -u origin <分支名>"
            ) | ForEach-Object { Add-LocalCandidate $_ }
        }
        "ssh" {
            @(
                "ssh <用户名>@<主机> -p <端口>",
                "ssh -i <私钥路径> <用户名>@<主机> -p <端口>",
                "ssh -L <本地端口>:127.0.0.1:<远端端口> <用户名>@<主机>",
                "ssh -R <远端端口>:127.0.0.1:<本地端口> <用户名>@<主机>"
            ) | ForEach-Object { Add-LocalCandidate $_ }
        }
        "docker" {
            @(
                "docker ps --format `"table {{.Names}}\t{{.Status}}\t{{.Ports}}`"",
                "docker logs -f <容器名或ID>",
                "docker exec -it <容器名或ID> sh",
                "docker compose up -d",
                "docker compose logs -f <服务名>"
            ) | ForEach-Object { Add-LocalCandidate $_ }
        }
        "npm" {
            @("npm install", "npm run dev", "npm run build", "npm test", "npm outdated") |
                ForEach-Object { Add-LocalCandidate $_ }
        }
        "python" {
            @("python -m venv .venv", "python -m pip install <包名>", "python -m pytest", "python <脚本.py>") |
                ForEach-Object { Add-LocalCandidate $_ }
        }
        "java" {
            @("java -version", "javac <文件.java>", "java -jar <文件.jar>") |
                ForEach-Object { Add-LocalCandidate $_ }
        }
        "adb" {
            @("adb devices", "adb shell", "adb logcat", "adb install <应用.apk>", "adb reverse tcp:<端口> tcp:<端口>") |
                ForEach-Object { Add-LocalCandidate $_ }
        }
    }

    if ($items.Count -eq 0 -and $text.Length -ge 2) {
        $items.Add("$text --help")
        if ($text -notmatch '\s') { $items.Add("Get-Command $text -Syntax") }
    }

    return @($items | Select-Object -First 6)
}

function Show-TerminalAiCompletionPopup {
    param([string]$Prefix)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $bg = [System.Drawing.Color]::FromArgb(18, 18, 18)
    $surface = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $fg = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $muted = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $accent = [System.Drawing.Color]::FromArgb(0, 122, 204)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = L '\u667a\u80fd\u8865\u5168'
    $form.StartPosition = "Manual"
    $form.FormBorderStyle = "FixedSingle"
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.BackColor = $bg
    $form.ForeColor = $fg
    $form.Size = New-Object System.Drawing.Size(720, 260)
    $form.KeyPreview = $true

    $point = Get-TerminalAiCursorScreenPoint
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = [Math]::Min([Math]::Max($screen.Left, $point.X), $screen.Right - $form.Width)
    $y = [Math]::Min([Math]::Max($screen.Top, $point.Y + 4), $screen.Bottom - $form.Height)
    $form.Location = New-Object System.Drawing.Point($x, $y)

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = "Fill"
    $root.RowCount = 4
    $root.ColumnCount = 1
    $root.Padding = New-Object System.Windows.Forms.Padding(8)
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = L '\u9009\u62e9\u5019\u9009\u547d\u4ee4\uff0c\u4e0b\u65b9\u53ef\u76f4\u63a5\u4fee\u6539\uff1bEnter \u63d2\u5165\uff0cEsc \u53d6\u6d88\u3002'
    $hint.Dock = "Fill"
    $hint.ForeColor = $muted
    $hint.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = "Fill"
    $list.BackColor = $surface
    $list.ForeColor = $fg
    $list.BorderStyle = "FixedSingle"
    $list.Font = New-Object System.Drawing.Font("Consolas", 10)

    $edit = New-Object System.Windows.Forms.TextBox
    $edit.Dock = "Fill"
    $edit.BackColor = [System.Drawing.Color]::Black
    $edit.ForeColor = $fg
    $edit.BorderStyle = "FixedSingle"
    $edit.Font = New-Object System.Drawing.Font("Consolas", 10)

    $bottom = New-Object System.Windows.Forms.FlowLayoutPanel
    $bottom.Dock = "Fill"
    $bottom.FlowDirection = "RightToLeft"
    $bottom.BackColor = $bg

    function New-CompletionButton([string]$Text) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Width = 86
        $button.Height = 28
        $button.FlatStyle = "Flat"
        $button.BackColor = $surface
        $button.ForeColor = $fg
        return $button
    }

    $insert = New-CompletionButton (L '\u63d2\u5165')
    $insert.BackColor = $accent
    $copy = New-CompletionButton (L '\u590d\u5236')
    $close = New-CompletionButton (L '\u53d6\u6d88')
    $status = New-Object System.Windows.Forms.Label
    $status.Text = L '\u672c\u5730\u5019\u9009\u5df2\u52a0\u8f7d\uff0cAI \u6b63\u5728\u540e\u53f0\u8865\u5145...'
    $status.AutoSize = $true
    $status.ForeColor = $muted
    $status.Padding = New-Object System.Windows.Forms.Padding(0, 7, 12, 0)

    [void]$bottom.Controls.Add($close)
    [void]$bottom.Controls.Add($copy)
    [void]$bottom.Controls.Add($insert)
    [void]$bottom.Controls.Add($status)

    [void]$root.Controls.Add($hint, 0, 0)
    [void]$root.Controls.Add($list, 0, 1)
    [void]$root.Controls.Add($edit, 0, 2)
    [void]$root.Controls.Add($bottom, 0, 3)
    [void]$form.Controls.Add($root)

    foreach ($item in (Get-TerminalAiLocalCompletions -Prefix $Prefix)) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $item
    }
    if ($list.Items.Count -eq 0) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $Prefix
    }
    $edit.Text = [string]$list.SelectedItem
    $edit.SelectionStart = $edit.TextLength

    $script:TaihCompletionChoice = $null
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $process = $null
    $argumentLine = (@($script:TaihCli, "complete", "--json", "--", $Prefix) | ForEach-Object { Q $_ }) -join " "

    if ($env:TAIH_TEST_NO_AI_COMPLETION -eq "1") {
        $status.Text = L '\u4ec5\u52a0\u8f7d\u672c\u5730\u5019\u9009'
    } else {
        try {
            $process = Start-Process -FilePath "node" -ArgumentList $argumentLine -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden -PassThru
        } catch {
            $status.Text = L 'AI \u8865\u5145\u542f\u52a8\u5931\u8d25\uff0c\u53ef\u5148\u7528\u672c\u5730\u5019\u9009'
        }
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 180
    if ($process) {
        $timer.Add_Tick({
            if (-not $process.HasExited) { return }
            $timer.Stop()
            try {
                if ($process.ExitCode -ne 0) {
                    $err = ""
                    try { $err = [System.IO.File]::ReadAllText($stderrFile, [System.Text.Encoding]::UTF8).Trim() } catch {}
                    if ($err.Length -gt 80) { $err = $err.Substring(0, 80) + "..." }
                    $status.Text = if ($err) { (L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009\uff1a') + $err } else { L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009' }
                    return
                }
                $raw = [System.IO.File]::ReadAllText($stdoutFile, [System.Text.Encoding]::UTF8)
                $result = $raw | ConvertFrom-Json
                $completion = [string]$result.completion
                if ($completion.Trim()) {
                    $full = if ($completion.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $completion } else { $Prefix + $completion }
                    Add-TerminalAiCompletionItem -ListBox $list -Value $full
                    $status.Text = L 'AI \u5019\u9009\u5df2\u52a0\u5165'
                } else {
                    $status.Text = L 'AI \u6ca1\u6709\u8fd4\u56de\u65b0\u5019\u9009'
                }
            } catch {
                $status.Text = L 'AI \u5019\u9009\u89e3\u6790\u5931\u8d25'
            } finally {
                Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
                try { $process.Dispose() } catch {}
            }
        })
        $timer.Start()
    }

    $list.Add_SelectedIndexChanged({
        if ($list.SelectedIndex -ge 0) {
            $edit.Text = [string]$list.SelectedItem
            $edit.SelectionStart = $edit.TextLength
        }
    })
    $accept = {
        $value = [string]$edit.Text
        if ($value.Trim()) {
            $script:TaihCompletionChoice = $value
            $form.Close()
        }
    }
    $insert.Add_Click($accept)
    $list.Add_DoubleClick($accept)
    $copy.Add_Click({ if ($edit.Text) { Set-Clipboard -Value $edit.Text; $status.Text = L '\u5df2\u590d\u5236' } })
    $close.Add_Click({ $form.Close() })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq "Escape") { $form.Close() }
        elseif ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; & $accept }
    })
    $form.Add_FormClosed({
        try { $timer.Stop(); $timer.Dispose() } catch {}
        if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    })

    if ($env:TAIH_TEST_COMPLETION_POPUP_NO_DIALOG -eq "1") {
        $script:TaihCompletionChoice = [string]$edit.Text
        try { $timer.Stop(); $timer.Dispose() } catch {}
        if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
        $form.Dispose()
        return $script:TaihCompletionChoice
    }

    [void]$form.ShowDialog()
    return $script:TaihCompletionChoice
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
    $form.Add_FormClosing({
        if ($script:TaihPanelTimer) {
            try { $script:TaihPanelTimer.Stop(); $script:TaihPanelTimer.Dispose() } catch {}
            $script:TaihPanelTimer = $null
        }
        if ($script:TaihPanelProcess -and -not $script:TaihPanelProcess.HasExited) {
            try { $script:TaihPanelProcess.Kill() } catch {}
            try { $script:TaihPanelProcess.Dispose() } catch {}
            $script:TaihPanelProcess = $null
        }
        if ($script:TaihPanelState) {
            Remove-Item -LiteralPath $script:TaihPanelState.StdoutFile, $script:TaihPanelState.StderrFile -Force -ErrorAction SilentlyContinue
            $script:TaihPanelState = $null
        }
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
    $split.SplitterDistance = 90
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

    $run.Add_Click({ Invoke-TerminalAiPanelRequest -ModeBox $mode -InputBox $commandBox -OutputBox $output -StatusLabel $status -ProgressBar $progress -HistoryBox $history -RunButton $run -ClipButton $clip })
    $commandBox.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; Invoke-TerminalAiPanelRequest -ModeBox $mode -InputBox $commandBox -OutputBox $output -StatusLabel $status -ProgressBar $progress -HistoryBox $history -RunButton $run -ClipButton $clip } })
    $clip.Add_Click({
        $clipText = Get-Clipboard -Raw
        if (-not $clipText -or -not $clipText.Trim()) {
            $status.Text = L '\u526a\u8d34\u677f\u4e3a\u7a7a'
            $output.Text = L '\u526a\u8d34\u677f\u4e3a\u7a7a\uff0c\u8bf7\u5148\u590d\u5236\u547d\u4ee4\u6216\u5728\u8f93\u5165\u6846\u624b\u52a8\u8f93\u5165\u3002'
            return
        }
        $commandBox.Text = $clipText
        Invoke-TerminalAiPanelRequest -ModeBox $mode -InputBox $commandBox -OutputBox $output -StatusLabel $status -ProgressBar $progress -HistoryBox $history -RunButton $run -ClipButton $clip
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
Ctrl+Space   $(L '\u6253\u5f00\u667a\u80fd\u8865\u5168\u5019\u9009\u6846')
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

function Get-TerminalAiForegroundRect {
    try {
        if (-not ("TaihWin32" -as [type])) {
            Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TaihWin32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
        }
        $hwnd = [TaihWin32]::GetForegroundWindow()
        $rect = New-Object TaihWin32+RECT
        if ([TaihWin32]::GetWindowRect($hwnd, [ref]$rect)) {
            return [pscustomobject]@{
                X = $rect.Left
                Y = $rect.Top
                W = $rect.Right - $rect.Left
                H = $rect.Bottom - $rect.Top
            }
        }
    } catch {}
    return [pscustomobject]@{ X = -1; Y = -1; W = -1; H = -1 }
}

function Get-TerminalAiForegroundHandle {
    try {
        if (-not ("TaihWin32" -as [type])) { [void](Get-TerminalAiForegroundRect) }
        return ([TaihWin32]::GetForegroundWindow().ToInt64())
    } catch {
        return 0
    }
}

function Ensure-TerminalAiWin32Extra {
    try {
        if ("TaihWin32Extra" -as [type]) { return }
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TaihWin32Extra {
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
    } catch {}
}

function Show-TerminalAiProcessWindow {
    param([int]$ProcessId)
    try {
        Ensure-TerminalAiWin32Extra
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $handle = $process.MainWindowHandle
        if ($handle -and $handle.ToInt64() -gt 0 -and [TaihWin32Extra]::IsWindow($handle)) {
            [TaihWin32Extra]::ShowWindow($handle, 5) | Out-Null
            [TaihWin32Extra]::SetForegroundWindow($handle) | Out-Null
            return $true
        }
    } catch {}
    return $false
}

function Get-TerminalAiCursorScreenPoint {
    $rect = Get-TerminalAiForegroundRect
    $left = 0
    $top = 0
    try {
        $left = [Console]::CursorLeft
        $top = [Console]::CursorTop
    } catch {}

    if ($rect.X -lt 0 -or $rect.W -le 0 -or $rect.H -le 0) {
        return [pscustomobject]@{ X = 160; Y = 160 }
    }

    $columns = [Math]::Max(1, [Console]::WindowWidth)
    $rows = [Math]::Max(1, [Console]::WindowHeight)
    $chromeTop = 78
    $cellW = [Math]::Max(7, [int](($rect.W - 24) / $columns))
    $cellH = [Math]::Max(16, [int](($rect.H - $chromeTop - 24) / $rows))
    $x = $rect.X + 16 + ($left * $cellW)
    $y = $rect.Y + $chromeTop + (($top + 1) * $cellH)
    return [pscustomobject]@{ X = $x; Y = $y }
}

function Add-TerminalAiCompletionItem {
    param($ListBox, [string]$Value)
    if (-not $Value -or -not $Value.Trim()) { return }
    $text = $Value.Trim()
    for ($i = 0; $i -lt $ListBox.Items.Count; $i++) {
        if ([string]$ListBox.Items[$i] -eq $text) { return }
    }
    [void]$ListBox.Items.Add($text)
    if ($ListBox.SelectedIndex -lt 0) { $ListBox.SelectedIndex = 0 }
}

function Show-TerminalAiCompletionPopup {
    param([string]$Prefix)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $bg = [System.Drawing.Color]::FromArgb(18, 18, 18)
    $surface = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $fg = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $muted = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $accent = [System.Drawing.Color]::FromArgb(0, 122, 204)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = L '\u667a\u80fd\u8865\u5168'
    $form.StartPosition = "Manual"
    $form.FormBorderStyle = "FixedSingle"
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.BackColor = $bg
    $form.ForeColor = $fg
    $form.Size = New-Object System.Drawing.Size(720, 260)
    $form.KeyPreview = $true

    $point = Get-TerminalAiCursorScreenPoint
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = [Math]::Min([Math]::Max($screen.Left, $point.X), $screen.Right - $form.Width)
    $y = [Math]::Min([Math]::Max($screen.Top, $point.Y + 4), $screen.Bottom - $form.Height)
    $form.Location = New-Object System.Drawing.Point($x, $y)

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = "Fill"
    $root.RowCount = 4
    $root.ColumnCount = 1
    $root.Padding = New-Object System.Windows.Forms.Padding(8)
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = L '\u9009\u62e9\u5019\u9009\u547d\u4ee4\uff0c\u4e0b\u65b9\u53ef\u76f4\u63a5\u4fee\u6539\uff1bEnter \u63d2\u5165\uff0cEsc \u53d6\u6d88\u3002'
    $hint.Dock = "Fill"
    $hint.ForeColor = $muted
    $hint.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = "Fill"
    $list.BackColor = $surface
    $list.ForeColor = $fg
    $list.BorderStyle = "FixedSingle"
    $list.Font = New-Object System.Drawing.Font("Consolas", 10)

    $edit = New-Object System.Windows.Forms.TextBox
    $edit.Dock = "Fill"
    $edit.BackColor = [System.Drawing.Color]::Black
    $edit.ForeColor = $fg
    $edit.BorderStyle = "FixedSingle"
    $edit.Font = New-Object System.Drawing.Font("Consolas", 10)

    $bottom = New-Object System.Windows.Forms.FlowLayoutPanel
    $bottom.Dock = "Fill"
    $bottom.FlowDirection = "RightToLeft"
    $bottom.BackColor = $bg

    function New-CompletionButton([string]$Text) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Width = 86
        $button.Height = 28
        $button.FlatStyle = "Flat"
        $button.BackColor = $surface
        $button.ForeColor = $fg
        return $button
    }

    $insert = New-CompletionButton (L '\u63d2\u5165')
    $insert.BackColor = $accent
    $copy = New-CompletionButton (L '\u590d\u5236')
    $close = New-CompletionButton (L '\u53d6\u6d88')
    $status = New-Object System.Windows.Forms.Label
    $status.Text = L '\u672c\u5730\u5019\u9009\u5df2\u52a0\u8f7d\uff0cAI \u6b63\u5728\u8865\u5145...'
    $status.AutoSize = $true
    $status.ForeColor = $muted
    $status.Padding = New-Object System.Windows.Forms.Padding(0, 7, 12, 0)

    [void]$bottom.Controls.Add($close)
    [void]$bottom.Controls.Add($copy)
    [void]$bottom.Controls.Add($insert)
    [void]$bottom.Controls.Add($status)

    [void]$root.Controls.Add($hint, 0, 0)
    [void]$root.Controls.Add($list, 0, 1)
    [void]$root.Controls.Add($edit, 0, 2)
    [void]$root.Controls.Add($bottom, 0, 3)
    [void]$form.Controls.Add($root)

    foreach ($item in (Get-TerminalAiLocalCompletions -Prefix $Prefix)) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $item
    }
    if ($list.Items.Count -eq 0) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $Prefix
    }
    $edit.Text = [string]$list.SelectedItem
    $edit.SelectionStart = $edit.TextLength

    $script:TaihCompletionChoice = $null
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $argumentLine = @($script:TaihCli, "complete", "--json", "--", $Prefix) | ForEach-Object { Q $_ }
    $argumentLine = $argumentLine -join " "
    $process = $null
    try {
        $process = Start-Process -FilePath "node" -ArgumentList $argumentLine -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden -PassThru
    } catch {
        $status.Text = L 'AI \u8865\u5145\u542f\u52a8\u5931\u8d25\uff0c\u53ef\u5148\u7528\u672c\u5730\u5019\u9009'
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 180
    if ($process) {
        $timer.Add_Tick({
            if (-not $process.HasExited) { return }
            $timer.Stop()
            try {
                if ($process.ExitCode -ne 0) {
                    $err = ""
                    try { $err = [System.IO.File]::ReadAllText($stderrFile, [System.Text.Encoding]::UTF8).Trim() } catch {}
                    if ($err.Length -gt 80) { $err = $err.Substring(0, 80) + "..." }
                    $status.Text = if ($err) { (L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009\uff1a') + $err } else { L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009' }
                    return
                }
                $raw = [System.IO.File]::ReadAllText($stdoutFile, [System.Text.Encoding]::UTF8)
                $result = $raw | ConvertFrom-Json
                $completion = [string]$result.completion
                if ($completion.Trim()) {
                    $full = if ($completion.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $completion } else { $Prefix + $completion }
                    Add-TerminalAiCompletionItem -ListBox $list -Value $full
                    $status.Text = L 'AI \u5019\u9009\u5df2\u52a0\u5165'
                } else {
                    $status.Text = L 'AI \u6ca1\u6709\u8fd4\u56de\u65b0\u5019\u9009'
                }
            } catch {
                $status.Text = L 'AI \u5019\u9009\u89e3\u6790\u5931\u8d25'
            } finally {
                Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
                try { $process.Dispose() } catch {}
            }
        })
        $timer.Start()
    }

    $list.Add_SelectedIndexChanged({
        if ($list.SelectedIndex -ge 0) {
            $edit.Text = [string]$list.SelectedItem
            $edit.SelectionStart = $edit.TextLength
        }
    })
    $accept = {
        $value = [string]$edit.Text
        if ($value.Trim()) {
            $script:TaihCompletionChoice = $value
            $form.Close()
        }
    }
    $insert.Add_Click($accept)
    $list.Add_DoubleClick($accept)
    $copy.Add_Click({ if ($edit.Text) { Set-Clipboard -Value $edit.Text; $status.Text = L '\u5df2\u590d\u5236' } })
    $close.Add_Click({ $form.Close() })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq "Escape") { $form.Close() }
        elseif ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; & $accept }
    })
    $form.Add_FormClosed({
        try { $timer.Stop(); $timer.Dispose() } catch {}
        if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    })

    [void]$form.ShowDialog()
    return $script:TaihCompletionChoice
}

function Show-TerminalAiPanel {
    param([string]$InitialText = "", [string]$Mode = "explain")

    $panelPath = Join-Path $script:TaihRoot "powershell\panel.ps1"
    if (-not (Test-Path -LiteralPath $panelPath)) {
        Write-Host ((L '\u627e\u4e0d\u5230\u9762\u677f\u811a\u672c\uff1a') + $panelPath) -ForegroundColor Red
        return
    }

    $inputFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($inputFile, [string]$InitialText, [System.Text.Encoding]::UTF8)
    $rect = Get-TerminalAiForegroundRect
    $anchorHandle = Get-TerminalAiForegroundHandle
    $panelId = if ($anchorHandle -gt 0) { "hwnd-$anchorHandle" } else { "pid-$PID" }
    $panelDir = Join-Path $env:USERPROFILE ".terminal-ai-helper\panels"
    New-Item -ItemType Directory -Path $panelDir -Force | Out-Null
    $commandFile = Join-Path $panelDir "$panelId.command.json"
    $pidFile = Join-Path $panelDir "$panelId.pid"
    $payload = [pscustomobject]@{
        inputFile = $inputFile
        mode = $Mode
        at = (Get-Date).ToString("o")
    }
    $payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $commandFile -Encoding UTF8
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $panelPath,
        "-InputFile", $inputFile,
        "-Mode", $Mode,
        "-PanelId", $panelId,
        "-AnchorHandle", [string]$anchorHandle,
        "-AnchorX", [string]$rect.X,
        "-AnchorY", [string]$rect.Y,
        "-AnchorW", [string]$rect.W,
        "-AnchorH", [string]$rect.H
    )
    if ($env:TAIH_TEST_NO_PANEL_START -eq "1") {
        $script:TaihLastPanelArgs = $args
        return
    }
    $existingPid = ""
    try { if (Test-Path -LiteralPath $pidFile) { $existingPid = (Get-Content -LiteralPath $pidFile -Raw).Trim() } } catch {}
    if ($existingPid) {
        $existing = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
        if ($existing) {
            if (Show-TerminalAiProcessWindow -ProcessId ([int]$existingPid)) {
                return
            }
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
    try {
        Start-Process -FilePath "powershell" -ArgumentList $args -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch {
        Write-Host ((L '\u9762\u677f\u542f\u52a8\u5931\u8d25\uff1a') + $_.Exception.Message) -ForegroundColor Red
        Write-Host "  powershell $($args -join ' ')" -ForegroundColor DarkGray
    }
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
        Show-TerminalAiPanel -InitialText $Text -Mode $Mode
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
function Show-TerminalAiUsageWindow { Show-TerminalAiPanel -InitialText (Get-TerminalAiContext) -Mode explain; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
function Show-TerminalAiFixWindow { $text = Get-TerminalAiContext; Show-TerminalAiPanel -InitialText $text -Mode fix; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
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
function Show-TerminalAiCompletionPopupForCurrentCommand {
    $state = Get-TerminalAiLineState
    $text = [string]$state.CurrentLine
    if (-not $text.Trim()) { return }
    try {
        $choice = Show-TerminalAiCompletionPopup -Prefix $text
        if ($choice -and $choice.Trim()) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($state.LineStart, $state.LineLength, $choice)
        }
    } catch {
        Write-Host ((L '\u8865\u5168\u5019\u9009\u6846\u5931\u8d25\uff1a') + $_.Exception.Message) -ForegroundColor Red
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

function Reset-TerminalAiPanels {
    $panelDir = Join-Path $env:USERPROFILE ".terminal-ai-helper\panels"
    if (Test-Path -LiteralPath $panelDir) {
        Remove-Item -Path (Join-Path $panelDir "*.pid"), (Join-Path $panelDir "*.command.json") -Force -ErrorAction SilentlyContinue
        Write-Host ((L '\u5df2\u6e05\u7406\u9762\u677f\u72b6\u6001\uff1a') + $panelDir) -ForegroundColor Green
    } else {
        Write-Host (L '\u6ca1\u6709\u627e\u5230\u9762\u677f\u72b6\u6001\u76ee\u5f55\u3002') -ForegroundColor Yellow
    }
}

function Show-TerminalAiKeyStatus {
    Write-Host (L '\u7ec8\u7aef AI \u52a9\u624b\u5feb\u6377\u952e\u72b6\u6001\uff1a') -ForegroundColor DarkCyan
    Write-Host "  Profile: $($PROFILE.CurrentUserCurrentHost)"
    Write-Host "  Script:  $PSCommandPath"
    Write-Host "  PSReadLine: $((Get-Module PSReadLine).Version)"
    Write-Host ""
    Get-PSReadLineKeyHandler -Bound |
        Where-Object { $_.Function -eq "CustomAction" -and $_.Key -in @("Alt+/", "Alt+?", "Ctrl+Spacebar", "Ctrl+Shift+Spacebar", "Alt+C", "Alt+Shift+C", "Alt+F", "Alt+Shift+F", "F2", "F3", "F4", "F8") } |
        Select-Object Key,Function,Description |
        Format-Table -AutoSize
    Write-Host (L '\u5982\u679c\u5217\u8868\u4e3a\u7a7a\uff0c\u8bf7\u5148\u8fd0\u884c\uff1a') -ForegroundColor Yellow
    Write-Host "  . `"$PSCommandPath`""
    Write-Host (L '\u5982 Alt/Ctrl \u7ec4\u5408\u952e\u65e0\u53cd\u5e94\uff0c\u901a\u5e38\u662f\u8f93\u5165\u6cd5\u6216 Windows Terminal \u62a2\u5360\uff1b\u8bf7\u8bd5 F2/F3/F4/F8 \u5907\u7528\u952e\u3002') -ForegroundColor Yellow
}

function Start-TerminalAiWhatKey {
    Write-Host (L '\u8bf7\u6309\u4e00\u4e2a\u9700\u8981\u8bca\u65ad\u7684\u5feb\u6377\u952e\uff0cPSReadLine \u4f1a\u663e\u793a\u5b83\u5b9e\u9645\u6536\u5230\u7684\u952e\u540d\u3002') -ForegroundColor Yellow
    try {
        [Microsoft.PowerShell.PSConsoleReadLine]::WhatIsKey()
    } catch {
        Write-Host ((L '\u6309\u952e\u8bca\u65ad\u65e0\u6cd5\u542f\u52a8\uff1a') + $_.Exception.Message) -ForegroundColor Red
        Write-Host (L '\u4f60\u4e5f\u53ef\u4ee5\u8fd0\u884c\uff1aGet-PSReadLineKeyHandler -Bound') -ForegroundColor Yellow
    }
}

function Get-TerminalAiLocalCompletions {
    param([string]$Prefix)

    $text = ([string]$Prefix).Trim()
    if (-not $text) { return @() }
    $command = ($text -split '\s+', 2)[0].ToLowerInvariant()
    $candidates = @()

    switch ($command) {
        "git" {
            $candidates = @(
                "git status -sb",
                "git log --oneline -5",
                ("git diff -- " + (L '\u003c\u6587\u4ef6\u8def\u5f84\u003e')),
                ("git add " + (L '\u003c\u6587\u4ef6\u8def\u5f84\u003e')),
                ("git commit -m `"" + (L '\u003c\u8bf4\u660e\u003e') + "`""),
                ("git push -u origin " + (L '\u003c\u5206\u652f\u540d\u003e'))
            )
        }
        "ssh" {
            $candidates = @(
                ("ssh " + (L '\u003c\u7528\u6237\u540d\u003e') + "@" + (L '\u003c\u4e3b\u673a\u003e') + " -p " + (L '\u003c\u7aef\u53e3\u003e')),
                ("ssh -i " + (L '\u003c\u79c1\u94a5\u8def\u5f84\u003e') + " " + (L '\u003c\u7528\u6237\u540d\u003e') + "@" + (L '\u003c\u4e3b\u673a\u003e') + " -p " + (L '\u003c\u7aef\u53e3\u003e')),
                ("ssh -L " + (L '\u003c\u672c\u5730\u7aef\u53e3\u003e') + ":127.0.0.1:" + (L '\u003c\u8fdc\u7aef\u7aef\u53e3\u003e') + " " + (L '\u003c\u7528\u6237\u540d\u003e') + "@" + (L '\u003c\u4e3b\u673a\u003e')),
                ("ssh -R " + (L '\u003c\u8fdc\u7aef\u7aef\u53e3\u003e') + ":127.0.0.1:" + (L '\u003c\u672c\u5730\u7aef\u53e3\u003e') + " " + (L '\u003c\u7528\u6237\u540d\u003e') + "@" + (L '\u003c\u4e3b\u673a\u003e'))
            )
        }
        "docker" {
            $candidates = @(
                "docker ps --format `"table {{.Names}}\t{{.Status}}\t{{.Ports}}`"",
                ("docker logs -f " + (L '\u003c\u5bb9\u5668\u540d\u6216ID\u003e')),
                ("docker exec -it " + (L '\u003c\u5bb9\u5668\u540d\u6216ID\u003e') + " sh"),
                "docker compose up -d",
                ("docker compose logs -f " + (L '\u003c\u670d\u52a1\u540d\u003e'))
            )
        }
        "npm" {
            $candidates = @("npm install", "npm run dev", "npm run build", "npm test", "npm outdated")
        }
        "python" {
            $candidates = @(
                "python -m venv .venv",
                ("python -m pip install " + (L '\u003c\u5305\u540d\u003e')),
                "python -m pytest",
                ("python " + (L '\u003c\u811a\u672c.py\u003e'))
            )
        }
        "java" {
            $candidates = @(
                "java -version",
                ("javac " + (L '\u003c\u6587\u4ef6.java\u003e')),
                ("java -jar " + (L '\u003c\u6587\u4ef6.jar\u003e'))
            )
        }
        "adb" {
            $candidates = @(
                "adb devices",
                "adb shell",
                "adb logcat",
                ("adb install " + (L '\u003c\u5e94\u7528.apk\u003e')),
                ("adb reverse tcp:" + (L '\u003c\u7aef\u53e3\u003e') + " tcp:" + (L '\u003c\u7aef\u53e3\u003e'))
            )
        }
        { $_ -in @("kube", "kubectl") } {
            $ns = L '\u003c\u547d\u540d\u7a7a\u95f4\u003e'
            $name = L '\u003c\u670d\u52a1\u540d\u003e'
            $pod = L '\u003cPod\u540d\u003e'
            $container = L '\u003c\u5bb9\u5668\u540d\u003e'
            $candidates = @(
                "$command get pods -A",
                "$command get svc -A",
                "$command get svc -n $ns",
                "$command get svc -o wide",
                "$command get svc -o yaml",
                "$command describe svc $name -n $ns",
                "$command get deploy -A",
                "$command logs -f $pod -n $ns",
                "$command logs -f $pod -c $container -n $ns",
                "$command exec -it $pod -n $ns -- sh"
            )
        }
    }

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if ($candidate.StartsWith($text, [System.StringComparison]::OrdinalIgnoreCase) -or $text -eq $command) {
            $items.Add($candidate)
        }
    }

    if ($items.Count -eq 0 -and $text.Length -ge 2) {
        $items.Add("$text --help")
        $items.Add("$text -h")
        if ($text -notmatch '\s') { $items.Add("Get-Command $text -Syntax") }
    }

    return @($items | Select-Object -First 6)
}

function Get-TerminalAiCursorScreenPoint {
    $rect = Get-TerminalAiForegroundRect
    $left = 0
    $top = 0
    $columns = 120
    $rows = 30
    try { $left = [Console]::CursorLeft } catch {}
    try { $top = [Console]::CursorTop } catch {}
    try { $columns = [Math]::Max(1, [Console]::WindowWidth) } catch {}
    try { $rows = [Math]::Max(1, [Console]::WindowHeight) } catch {}

    if ($rect.X -lt 0 -or $rect.W -le 0 -or $rect.H -le 0) {
        return [pscustomobject]@{ X = 160; Y = 160 }
    }

    $chromeTop = 78
    $cellW = [Math]::Max(7, [int](($rect.W - 24) / $columns))
    $cellH = [Math]::Max(16, [int](($rect.H - $chromeTop - 24) / $rows))
    $x = $rect.X + 16 + ($left * $cellW)
    $y = $rect.Y + $chromeTop + (($top + 1) * $cellH)
    return [pscustomobject]@{ X = $x; Y = $y }
}

function Show-TerminalAiCompletionPopup {
    param([string]$Prefix)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $bg = [System.Drawing.Color]::FromArgb(18, 18, 18)
    $surface = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $fg = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $muted = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $accent = [System.Drawing.Color]::FromArgb(0, 122, 204)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = L '\u667a\u80fd\u8865\u5168'
    $form.StartPosition = "Manual"
    $form.FormBorderStyle = "FixedSingle"
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.BackColor = $bg
    $form.ForeColor = $fg
    $form.Size = New-Object System.Drawing.Size(720, 260)
    $form.KeyPreview = $true

    $point = Get-TerminalAiCursorScreenPoint
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = [Math]::Min([Math]::Max($screen.Left, $point.X), $screen.Right - $form.Width)
    $y = [Math]::Min([Math]::Max($screen.Top, $point.Y + 4), $screen.Bottom - $form.Height)
    $form.Location = New-Object System.Drawing.Point($x, $y)

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = "Fill"
    $root.RowCount = 4
    $root.ColumnCount = 1
    $root.Padding = New-Object System.Windows.Forms.Padding(8)
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = L '\u9009\u62e9\u5019\u9009\u547d\u4ee4\uff0c\u4e0b\u65b9\u53ef\u76f4\u63a5\u4fee\u6539\uff1bEnter \u63d2\u5165\uff0cEsc \u53d6\u6d88\u3002'
    $hint.Dock = "Fill"
    $hint.ForeColor = $muted
    $hint.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = "Fill"
    $list.BackColor = $surface
    $list.ForeColor = $fg
    $list.BorderStyle = "FixedSingle"
    $list.Font = New-Object System.Drawing.Font("Consolas", 10)

    $edit = New-Object System.Windows.Forms.TextBox
    $edit.Dock = "Fill"
    $edit.BackColor = [System.Drawing.Color]::Black
    $edit.ForeColor = $fg
    $edit.BorderStyle = "FixedSingle"
    $edit.Font = New-Object System.Drawing.Font("Consolas", 10)

    $bottom = New-Object System.Windows.Forms.FlowLayoutPanel
    $bottom.Dock = "Fill"
    $bottom.FlowDirection = "RightToLeft"
    $bottom.BackColor = $bg

    function New-CompletionButton([string]$Text) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Width = 86
        $button.Height = 28
        $button.FlatStyle = "Flat"
        $button.BackColor = $surface
        $button.ForeColor = $fg
        return $button
    }

    $insert = New-CompletionButton (L '\u63d2\u5165')
    $insert.BackColor = $accent
    $copy = New-CompletionButton (L '\u590d\u5236')
    $close = New-CompletionButton (L '\u53d6\u6d88')
    $status = New-Object System.Windows.Forms.Label
    $status.Text = L '\u672c\u5730\u5019\u9009\u5df2\u52a0\u8f7d\uff0cAI \u6b63\u5728\u540e\u53f0\u8865\u5145...'
    $status.AutoSize = $true
    $status.ForeColor = $muted
    $status.Padding = New-Object System.Windows.Forms.Padding(0, 7, 12, 0)

    [void]$bottom.Controls.Add($close)
    [void]$bottom.Controls.Add($copy)
    [void]$bottom.Controls.Add($insert)
    [void]$bottom.Controls.Add($status)
    [void]$root.Controls.Add($hint, 0, 0)
    [void]$root.Controls.Add($list, 0, 1)
    [void]$root.Controls.Add($edit, 0, 2)
    [void]$root.Controls.Add($bottom, 0, 3)
    [void]$form.Controls.Add($root)

    foreach ($item in (Get-TerminalAiLocalCompletions -Prefix $Prefix)) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $item
    }
    if ($list.Items.Count -eq 0) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $Prefix
    }
    $edit.Text = [string]$list.SelectedItem
    $edit.SelectionStart = $edit.TextLength

    $script:TaihCompletionChoice = $null
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $process = $null

    if ($env:TAIH_TEST_NO_AI_COMPLETION -eq "1") {
        $status.Text = L '\u4ec5\u52a0\u8f7d\u672c\u5730\u5019\u9009'
    } else {
        $argumentLine = (@($script:TaihCli, "complete", "--json", "--", $Prefix) | ForEach-Object { Q $_ }) -join " "
        try {
            $process = Start-Process -FilePath "node" -ArgumentList $argumentLine -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden -PassThru
        } catch {
            $status.Text = L 'AI \u8865\u5145\u542f\u52a8\u5931\u8d25\uff0c\u53ef\u5148\u7528\u672c\u5730\u5019\u9009'
        }
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 180
    if ($process) {
        $timer.Add_Tick({
            if (-not $process.HasExited) { return }
            $timer.Stop()
            try {
                if ($process.ExitCode -ne 0) {
                    $err = ""
                    try { $err = [System.IO.File]::ReadAllText($stderrFile, [System.Text.Encoding]::UTF8).Trim() } catch {}
                    if ($err.Length -gt 80) { $err = $err.Substring(0, 80) + "..." }
                    $status.Text = if ($err) { (L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009\uff1a') + $err } else { L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009' }
                    return
                }
                $raw = [System.IO.File]::ReadAllText($stdoutFile, [System.Text.Encoding]::UTF8)
                $result = $raw | ConvertFrom-Json
                $completion = [string]$result.completion
                if ($completion.Trim()) {
                    $full = if ($completion.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $completion } else { $Prefix + $completion }
                    Add-TerminalAiCompletionItem -ListBox $list -Value $full
                    $status.Text = L 'AI \u5019\u9009\u5df2\u52a0\u5165'
                } else {
                    $status.Text = L 'AI \u6ca1\u6709\u8fd4\u56de\u65b0\u5019\u9009'
                }
            } catch {
                $status.Text = L 'AI \u5019\u9009\u89e3\u6790\u5931\u8d25'
            } finally {
                Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
                try { $process.Dispose() } catch {}
            }
        })
        $timer.Start()
    }

    $list.Add_SelectedIndexChanged({
        if ($list.SelectedIndex -ge 0) {
            $edit.Text = [string]$list.SelectedItem
            $edit.SelectionStart = $edit.TextLength
        }
    })
    $accept = {
        $value = [string]$edit.Text
        if ($value.Trim()) {
            $script:TaihCompletionChoice = $value
            $form.Close()
        }
    }
    $insert.Add_Click($accept)
    $list.Add_DoubleClick($accept)
    $copy.Add_Click({ if ($edit.Text) { Set-Clipboard -Value $edit.Text; $status.Text = L '\u5df2\u590d\u5236' } })
    $close.Add_Click({ $form.Close() })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq "Escape") { $form.Close() }
        elseif ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; & $accept }
    })
    $form.Add_FormClosed({
        try { $timer.Stop(); $timer.Dispose() } catch {}
        if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    })

    if ($env:TAIH_TEST_COMPLETION_POPUP_NO_DIALOG -eq "1") {
        $script:TaihCompletionChoice = [string]$edit.Text
        try { $timer.Stop(); $timer.Dispose() } catch {}
        if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
        $form.Dispose()
        return $script:TaihCompletionChoice
    }

    [void]$form.ShowDialog()
    return $script:TaihCompletionChoice
}

function Show-TerminalAiCompletionPopup {
    param([string]$Prefix)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $bg = [System.Drawing.Color]::FromArgb(18, 18, 18)
    $surface = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $fg = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $muted = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $accent = [System.Drawing.Color]::FromArgb(0, 122, 204)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = L '\u667a\u80fd\u8865\u5168'
    $form.StartPosition = "Manual"
    $form.FormBorderStyle = "FixedSingle"
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.BackColor = $bg
    $form.ForeColor = $fg
    $form.Size = New-Object System.Drawing.Size(760, 260)
    $form.KeyPreview = $true

    $point = Get-TerminalAiCursorScreenPoint
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = [Math]::Min([Math]::Max($screen.Left, $point.X), $screen.Right - $form.Width)
    $y = [Math]::Min([Math]::Max($screen.Top, $point.Y + 2), $screen.Bottom - $form.Height)
    $form.Location = New-Object System.Drawing.Point($x, $y)

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = "Fill"
    $root.RowCount = 4
    $root.ColumnCount = 1
    $root.Padding = New-Object System.Windows.Forms.Padding(8)
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = L '\u672c\u5730\u5019\u9009\u7acb\u5373\u663e\u793a\uff0cAI \u5019\u9009\u540e\u53f0\u8ffd\u52a0\uff1bEnter \u63d2\u5165\uff0cEsc \u53d6\u6d88\u3002'
    $hint.Dock = "Fill"
    $hint.ForeColor = $muted
    $hint.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = "Fill"
    $list.BackColor = $surface
    $list.ForeColor = $fg
    $list.BorderStyle = "FixedSingle"
    $list.Font = New-Object System.Drawing.Font("Consolas", 10)

    $edit = New-Object System.Windows.Forms.TextBox
    $edit.Dock = "Fill"
    $edit.BackColor = [System.Drawing.Color]::Black
    $edit.ForeColor = $fg
    $edit.BorderStyle = "FixedSingle"
    $edit.Font = New-Object System.Drawing.Font("Consolas", 10)

    $bottom = New-Object System.Windows.Forms.FlowLayoutPanel
    $bottom.Dock = "Fill"
    $bottom.FlowDirection = "RightToLeft"
    $bottom.BackColor = $bg

    function New-CompletionButton([string]$Text) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Width = 86
        $button.Height = 28
        $button.FlatStyle = "Flat"
        $button.BackColor = $surface
        $button.ForeColor = $fg
        return $button
    }

    function Expand-CompletionCandidate([string]$Candidate) {
        $value = ([string]$Candidate).Trim()
        if (-not $value) { return "" }
        if ($value.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $value }
        if ($value -match '^\S+(\s|$)' -and $value.Contains(" ")) { return $value }
        return $Prefix + $value
    }

    $insert = New-CompletionButton (L '\u63d2\u5165')
    $insert.BackColor = $accent
    $copy = New-CompletionButton (L '\u590d\u5236')
    $close = New-CompletionButton (L '\u53d6\u6d88')
    $status = New-Object System.Windows.Forms.Label
    $status.Text = L '\u672c\u5730\u5019\u9009\u5df2\u52a0\u8f7d\uff0cAI \u6b63\u5728\u540e\u53f0\u8865\u5145...'
    $status.AutoSize = $true
    $status.ForeColor = $muted
    $status.Padding = New-Object System.Windows.Forms.Padding(0, 7, 12, 0)

    [void]$bottom.Controls.Add($close)
    [void]$bottom.Controls.Add($copy)
    [void]$bottom.Controls.Add($insert)
    [void]$bottom.Controls.Add($status)
    [void]$root.Controls.Add($hint, 0, 0)
    [void]$root.Controls.Add($list, 0, 1)
    [void]$root.Controls.Add($edit, 0, 2)
    [void]$root.Controls.Add($bottom, 0, 3)
    [void]$form.Controls.Add($root)

    foreach ($item in (Get-TerminalAiLocalCompletions -Prefix $Prefix)) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $item
    }
    if ($list.Items.Count -eq 0) {
        Add-TerminalAiCompletionItem -ListBox $list -Value $Prefix
    }
    $edit.Text = [string]$list.SelectedItem
    $edit.SelectionStart = $edit.TextLength

    $script:TaihCompletionChoice = $null
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $process = $null

    if ($env:TAIH_TEST_NO_AI_COMPLETION -eq "1") {
        $status.Text = L '\u4ec5\u52a0\u8f7d\u672c\u5730\u5019\u9009'
    } else {
        $argumentLine = (@($script:TaihCli, "complete", "--json", "--", $Prefix) | ForEach-Object { Q $_ }) -join " "
        try {
            $process = Start-Process -FilePath "node" -ArgumentList $argumentLine -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -WindowStyle Hidden -PassThru
        } catch {
            $status.Text = L 'AI \u8865\u5145\u542f\u52a8\u5931\u8d25\uff0c\u53ef\u5148\u7528\u672c\u5730\u5019\u9009'
        }
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 180
    if ($process) {
        $timer.Add_Tick({
            if (-not $process.HasExited) { return }
            $timer.Stop()
            try {
                if ($process.ExitCode -ne 0) {
                    $err = ""
                    try { $err = [System.IO.File]::ReadAllText($stderrFile, [System.Text.Encoding]::UTF8).Trim() } catch {}
                    if ($err.Length -gt 100) { $err = $err.Substring(0, 100) + "..." }
                    $status.Text = if ($err) { (L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009\uff1a') + $err } else { L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009' }
                    return
                }
                $raw = [System.IO.File]::ReadAllText($stdoutFile, [System.Text.Encoding]::UTF8)
                $result = $raw | ConvertFrom-Json
                $before = $list.Items.Count
                $candidates = New-Object System.Collections.Generic.List[string]
                if ($result.completion) { [void]$candidates.Add([string]$result.completion) }
                if ($result.completions) {
                    foreach ($item in @($result.completions)) { [void]$candidates.Add([string]$item) }
                }
                if ($result.examples) {
                    foreach ($item in @($result.examples)) {
                        if ($item.command) { [void]$candidates.Add([string]$item.command) }
                    }
                }
                foreach ($candidate in $candidates) {
                    $full = Expand-CompletionCandidate $candidate
                    Add-TerminalAiCompletionItem -ListBox $list -Value $full
                }
                $added = $list.Items.Count - $before
                $status.Text = if ($added -gt 0) { (L 'AI \u5019\u9009\u5df2\u52a0\u5165\uff1a') + $added } else { L 'AI \u6ca1\u6709\u8fd4\u56de\u65b0\u5019\u9009' }
            } catch {
                $status.Text = (L 'AI \u5019\u9009\u89e3\u6790\u5931\u8d25\uff1a') + $_.Exception.Message
            } finally {
                Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
                try { $process.Dispose() } catch {}
            }
        })
        $timer.Start()
    }

    $list.Add_SelectedIndexChanged({
        if ($list.SelectedIndex -ge 0) {
            $edit.Text = [string]$list.SelectedItem
            $edit.SelectionStart = $edit.TextLength
        }
    })
    $accept = {
        $value = [string]$edit.Text
        if ($value.Trim()) {
            $script:TaihCompletionChoice = $value
            $form.Close()
        }
    }
    $insert.Add_Click($accept)
    $list.Add_DoubleClick($accept)
    $copy.Add_Click({ if ($edit.Text) { Set-Clipboard -Value $edit.Text; $status.Text = L '\u5df2\u590d\u5236' } })
    $close.Add_Click({ $form.Close() })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq "Escape") { $form.Close() }
        elseif ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; & $accept }
    })
    $form.Add_FormClosed({
        try { $timer.Stop(); $timer.Dispose() } catch {}
        if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    })

    if ($env:TAIH_TEST_COMPLETION_POPUP_NO_DIALOG -eq "1") {
        $script:TaihCompletionChoice = [string]$edit.Text
        try { $timer.Stop(); $timer.Dispose() } catch {}
        if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
        $form.Dispose()
        return $script:TaihCompletionChoice
    }

    [void]$form.ShowDialog()
    return $script:TaihCompletionChoice
}

Set-PSReadLineKeyHandler -Chord "Alt+/" -ScriptBlock { Show-TerminalAiUsage }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+/" -ScriptBlock { Show-TerminalAiUsageWindow }
Set-PSReadLineKeyHandler -Chord "Alt+?" -ScriptBlock { Show-TerminalAiPanel }
Set-PSReadLineKeyHandler -Chord "Ctrl+Spacebar" -ScriptBlock { Show-TerminalAiCompletionPopupForCurrentCommand }
try { Set-PSReadLineKeyHandler -Chord "Ctrl+Shift+Spacebar" -ScriptBlock { Show-TerminalAiCompletionPopupForCurrentCommand } } catch {}
Set-PSReadLineKeyHandler -Chord "Alt+C" -ScriptBlock { Copy-TerminalAiCompletion }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+C" -ScriptBlock { Copy-TerminalAiCompletion }
Set-PSReadLineKeyHandler -Chord "Alt+F" -ScriptBlock { Show-TerminalAiFixWindow }
Set-PSReadLineKeyHandler -Chord "Alt+Shift+F" -ScriptBlock { Show-TerminalAiFixWindow }
Set-PSReadLineKeyHandler -Chord "F2" -ScriptBlock { Show-TerminalAiUsage }
Set-PSReadLineKeyHandler -Chord "F3" -ScriptBlock { Show-TerminalAiPanel }
Set-PSReadLineKeyHandler -Chord "F4" -ScriptBlock { Show-TerminalAiCompletionPopupForCurrentCommand }
Set-PSReadLineKeyHandler -Chord "F8" -ScriptBlock { Show-TerminalAiFixWindow }

Set-Alias taih-current Show-TerminalAiUsage -Force
Set-Alias taih-popup Show-TerminalAiUsageWindow -Force
Set-Alias taih-panel Show-TerminalAiPanel -Force
Set-Alias taih-clip Invoke-TerminalAiClipboard -Force
Set-Alias taih-fix Show-TerminalAiFixWindow -Force
Set-Alias taih-keys Show-TerminalAiKeyStatus -Force
Set-Alias taih-what-key Start-TerminalAiWhatKey -Force
Set-Alias taih-complete-popup Show-TerminalAiCompletionPopupForCurrentCommand -Force
Set-Alias taih-complete-stable Complete-TerminalAiCommand -Force
Set-Alias taih-panel-reset Reset-TerminalAiPanels -Force

Write-Host (L '\u7ec8\u7aef AI \u52a9\u624b\u5df2\u52a0\u8f7d\uff1a') -ForegroundColor DarkCyan
Write-Host (L '  Alt+/        \u89e3\u91ca\u9009\u4e2d\u6587\u672c\u6216\u5f53\u524d\u547d\u4ee4')
Write-Host (L '  Alt+?        \u6253\u5f00\u7ba1\u7406\u9762\u677f\uff08\u5f88\u591a\u952e\u76d8\u4e0a Alt+Shift+/ \u4f1a\u663e\u793a\u4e3a Alt+?\uff09')
Write-Host (L '  Ctrl+Space   \u6253\u5f00\u667a\u80fd\u8865\u5168\u5019\u9009\u6846\uff08\u5148\u672c\u5730\uff0cAI \u540e\u53f0\u8865\u5145\uff09')
Write-Host (L '  Ctrl+Shift+Space  \u5907\u7528\u8865\u5168\u5019\u9009\uff08Ctrl+Space \u88ab\u8f93\u5165\u6cd5\u62a2\u5360\u65f6\u7528\uff09')
Write-Host (L '  Alt+C        \u590d\u5236 AI \u8865\u5168\uff08Alt+Shift+C \u5728\u67d0\u4e9b\u7ec8\u7aef\u4f1a\u88ab\u8bc6\u522b\u4e3a Alt+C\uff09')
Write-Host (L '  Alt+F        \u8bca\u65ad\u9009\u4e2d\u6587\u672c\u6216\u5f53\u524d\u547d\u4ee4\uff08Alt+Shift+F \u540c\u7406\uff09')
Write-Host (L '  F2/F3/F4/F8  \u5907\u7528\uff1a\u89e3\u91ca/\u9762\u677f/\u8865\u5168\u5019\u9009/\u8bca\u65ad')
Write-Host (L '  taih-complete-popup  \u624b\u52a8\u6253\u5f00\u53ef\u7f16\u8f91\u8865\u5168\u5019\u9009\u6846')
Write-Host (L '  taih-complete-stable \u4e0d\u5f39\u7a97\uff0c\u76f4\u63a5\u8bf7\u6c42 AI \u5e76\u63d2\u5165\u8865\u5168')
Write-Host (L '  taih-panel-reset     \u6e05\u7406\u5361\u4f4f\u7684\u9762\u677f\u72b6\u6001')
