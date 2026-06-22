param(
    [string]$Target = "root@us-vpn",
    [string]$Command = "",
    [string]$Tools = "linux,ssh,systemd,k8s,docker",
    [string]$RemoteShell = "bash",
    [switch]$SmokeTest,
    [string]$SmokeCommand = "hostname && uptime && whoami"
)

$ErrorActionPreference = "Stop"
$script:TaihRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script:TaihCli = Join-Path $script:TaihRoot "bin\taih.js"
$script:SshProcess = $null
$script:AiProcess = $null
$script:SshTimer = $null
$script:AiTimer = $null
$script:SshState = $null
$script:AiState = $null

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

function New-TempFilePath { return [System.IO.Path]::GetTempFileName() }

function Build-SshArguments {
    param([string]$Target, [string]$Shell, [string]$Command)
    $shellValue = $Shell
    if (-not $shellValue) { $shellValue = "bash" }
    return @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ServerAliveInterval=15",
        $Target,
        "--",
        $shellValue,
        "-lc",
        $Command
    )
}

function Invoke-SshCapture {
    param([string]$Target, [string]$Shell, [string]$Command)
    $arguments = Build-SshArguments -Target $Target -Shell $Shell -Command $Command
    $output = & ssh @arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join "`n")
    }
}

function Stop-ChildProcess {
    param($Process)
    if ($Process -and -not $Process.HasExited) {
        try { $Process.Kill() } catch {}
    }
}

function Start-FileProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$StdoutFile,
        [string]$StderrFile
    )
    $argumentLine = ($Arguments | ForEach-Object { Q $_ }) -join " "
    return Start-Process -FilePath $FilePath -ArgumentList $argumentLine -RedirectStandardOutput $StdoutFile -RedirectStandardError $StderrFile -WindowStyle Hidden -PassThru
}

function Append-Text {
    param($Box, [string]$Text)
    if (-not $Text) { return }
    $Box.AppendText($Text)
    $Box.SelectionStart = $Box.TextLength
    $Box.ScrollToCaret()
}

function New-Button {
    param([string]$Text, [int]$Width = 92)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 30
    $button.FlatStyle = "Flat"
    $button.BackColor = $script:Surface
    $button.ForeColor = $script:Fg
    return $button
}

function Read-NewText {
    param([string]$Path, [int]$LastLength)
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            return [pscustomobject]@{ Text = ""; Length = $LastLength }
        }
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ($text.Length -le $LastLength) {
            return [pscustomobject]@{ Text = ""; Length = $LastLength }
        }
        return [pscustomobject]@{ Text = $text.Substring($LastLength); Length = $text.Length }
    } catch {
        return [pscustomobject]@{ Text = ""; Length = $LastLength }
    }
}

function Start-RemoteCommand {
    param($TargetBox, $ShellBox, $CommandBox, $TerminalBox, $StatusLabel, $TaskBox)
    if ($script:SshProcess -and -not $script:SshProcess.HasExited) {
        $StatusLabel.Text = L '\u8fdc\u7aef\u547d\u4ee4\u6b63\u5728\u6267\u884c'
        return
    }
    $target = [string]$TargetBox.Text
    $commandText = [string]$CommandBox.Text
    if (-not $target.Trim() -or -not $commandText.Trim()) {
        $StatusLabel.Text = L '\u8bf7\u586b\u5199 SSH \u76ee\u6807\u548c\u547d\u4ee4'
        return
    }

    $TerminalBox.Clear()
    Append-Text $TerminalBox ("[$target]`$ " + $commandText + "`r`n`r`n")
    $StatusLabel.Text = L '\u6b63\u5728\u6267\u884c\u8fdc\u7aef\u547d\u4ee4...'
    [void]$TaskBox.Items.Insert(0, ((L '\u6267\u884c: ') + $commandText))

    $stdoutFile = New-TempFilePath
    $stderrFile = New-TempFilePath
    $arguments = Build-SshArguments -Target $target -Shell ([string]$ShellBox.Text) -Command $commandText
    $process = Start-FileProcess -FilePath "ssh" -Arguments $arguments -StdoutFile $stdoutFile -StderrFile $stderrFile
    $script:SshProcess = $process
    $script:SshState = [pscustomobject]@{
        Process = $process
        StdoutFile = $stdoutFile
        StderrFile = $stderrFile
        LastOutLength = 0
        LastErrLength = 0
        Started = Get-Date
        TerminalBox = $TerminalBox
        StatusLabel = $StatusLabel
        TaskBox = $TaskBox
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 220
    $script:SshTimer = $timer
    $timer.Add_Tick({
        $state = $script:SshState
        if (-not $state) { return }

        $out = Read-NewText -Path $state.StdoutFile -LastLength $state.LastOutLength
        if ($out.Text) {
            $state.LastOutLength = $out.Length
            Append-Text $state.TerminalBox $out.Text
        }
        $err = Read-NewText -Path $state.StderrFile -LastLength $state.LastErrLength
        if ($err.Text) {
            $state.LastErrLength = $err.Length
            Append-Text $state.TerminalBox ("[stderr] " + $err.Text)
        }

        if (-not $state.Process.HasExited) { return }
        $script:SshTimer.Stop()
        $script:SshTimer.Dispose()
        $script:SshTimer = $null
        $seconds = [Math]::Round(((Get-Date) - $state.Started).TotalSeconds, 1)
        $state.StatusLabel.Text = (L '\u8fdc\u7aef\u547d\u4ee4\u5b8c\u6210\uff0c\u9000\u51fa\u7801 ') + $state.Process.ExitCode + (L '\uff0c\u7528\u65f6 ') + $seconds + "s"
        [void]$state.TaskBox.Items.Insert(0, ("done: exit=" + $state.Process.ExitCode + " " + $seconds + "s"))
        Remove-Item -LiteralPath $state.StdoutFile, $state.StderrFile -Force -ErrorAction SilentlyContinue
        try { $state.Process.Dispose() } catch {}
        $script:SshProcess = $null
        $script:SshState = $null
    })
    $timer.Start()
}

function Start-AiRequest {
    param($Mode, $Text, $ToolsBox, $AiBox, $StatusLabel, $TaskBox)
    if ($script:AiProcess -and -not $script:AiProcess.HasExited) {
        $StatusLabel.Text = L 'AI \u6b63\u5728\u751f\u6210'
        return
    }
    if (-not ([string]$Text).Trim()) {
        $StatusLabel.Text = L '\u6ca1\u6709\u53ef\u5206\u6790\u6587\u672c'
        return
    }
    $AiBox.Clear()
    $StatusLabel.Text = L 'AI \u6b63\u5728\u751f\u6210...'
    [void]$TaskBox.Items.Insert(0, ("AI: " + $Mode))

    $stdoutFile = New-TempFilePath
    $stderrFile = New-TempFilePath
    $toolsValue = [string]$ToolsBox.Text
    if (-not $toolsValue.Trim()) { $toolsValue = "linux,ssh,systemd,k8s,docker" }
    $arguments = @($script:TaihCli, $Mode, "--stream", "--style", "brief", "--tools", $toolsValue, "--", $Text)
    $process = Start-FileProcess -FilePath "node" -Arguments $arguments -StdoutFile $stdoutFile -StderrFile $stderrFile
    $script:AiProcess = $process
    $script:AiState = [pscustomobject]@{
        Process = $process
        StdoutFile = $stdoutFile
        StderrFile = $stderrFile
        LastLength = 0
        Started = Get-Date
        AiBox = $AiBox
        StatusLabel = $StatusLabel
        TaskBox = $TaskBox
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 220
    $script:AiTimer = $timer
    $timer.Add_Tick({
        $state = $script:AiState
        if (-not $state) { return }
        $out = Read-NewText -Path $state.StdoutFile -LastLength $state.LastLength
        if ($out.Text) {
            $state.LastLength = $out.Length
            Append-Text $state.AiBox $out.Text
        }
        if (-not $state.Process.HasExited) { return }
        $script:AiTimer.Stop()
        $script:AiTimer.Dispose()
        $script:AiTimer = $null
        $err = ""
        try {
            if (Test-Path -LiteralPath $state.StderrFile) {
                $err = [System.IO.File]::ReadAllText($state.StderrFile, [System.Text.Encoding]::UTF8)
            }
        } catch {}
        if ($err.Trim()) { Append-Text $state.AiBox ("`r`n[AI error] " + $err.Trim() + "`r`n") }
        $seconds = [Math]::Round(((Get-Date) - $state.Started).TotalSeconds, 1)
        $state.StatusLabel.Text = (L 'AI \u5b8c\u6210\uff0c\u7528\u65f6 ') + $seconds + "s"
        [void]$state.TaskBox.Items.Insert(0, ("AI done: " + $seconds + "s"))
        Remove-Item -LiteralPath $state.StdoutFile, $state.StderrFile -Force -ErrorAction SilentlyContinue
        try { $state.Process.Dispose() } catch {}
        $script:AiProcess = $null
        $script:AiState = $null
    })
    $timer.Start()
}

if ($SmokeTest) {
    $result = Invoke-SshCapture -Target $Target -Shell $RemoteShell -Command $SmokeCommand
    if ($result.ExitCode -ne 0) {
        throw ("SSH smoke test failed: exit=" + $result.ExitCode + " " + $result.Output)
    }
    Write-Host "ssh smoke ok"
    Write-Host $result.Output
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Bg = [System.Drawing.Color]::FromArgb(245, 247, 250)
$script:Surface = [System.Drawing.Color]::FromArgb(255, 255, 255)
$script:Panel = [System.Drawing.Color]::FromArgb(238, 242, 247)
$script:Fg = [System.Drawing.Color]::FromArgb(25, 35, 50)
$script:Muted = [System.Drawing.Color]::FromArgb(90, 105, 125)
$script:Accent = [System.Drawing.Color]::FromArgb(24, 119, 242)
$script:TerminalBg = [System.Drawing.Color]::FromArgb(10, 10, 10)
$script:TerminalFg = [System.Drawing.Color]::FromArgb(220, 220, 220)

function New-Label {
    param([string]$Text)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Dock = "Fill"
    $label.TextAlign = "MiddleLeft"
    $label.ForeColor = $script:Muted
    return $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = L '\u7ec8\u7aef AI \u8fdc\u7aef\u63a7\u5236\u9762\u677f'
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1320, 820)
$form.MinimumSize = New-Object System.Drawing.Size(980, 620)
$form.BackColor = $script:Bg
$form.ForeColor = $script:Fg
$form.Add_FormClosing({
    Stop-ChildProcess $script:SshProcess
    Stop-ChildProcess $script:AiProcess
})

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = "Fill"
$root.RowCount = 3
$root.ColumnCount = 1
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))

$title = New-Object System.Windows.Forms.Label
$title.Text = L '  \u7ec8\u7aef AI \u8fdc\u7aef\u63a7\u5236\u9762\u677f    \u672c\u5730\u684c\u9762\u64cd\u4f5c SSH \u670d\u52a1\u5668'
$title.Dock = "Fill"
$title.TextAlign = "MiddleLeft"
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
$title.BackColor = $script:Surface
$title.ForeColor = $script:Fg

$main = New-Object System.Windows.Forms.SplitContainer
$main.Dock = "Fill"
$main.Orientation = "Vertical"
$main.SplitterDistance = 880
$main.BackColor = $script:Bg

$left = New-Object System.Windows.Forms.TableLayoutPanel
$left.Dock = "Fill"
$left.RowCount = 3
$left.ColumnCount = 1
[void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 190)))

$topBar = New-Object System.Windows.Forms.TableLayoutPanel
$topBar.Dock = "Fill"
$topBar.ColumnCount = 6
[void]$topBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 72)))
[void]$topBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 40)))
[void]$topBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 64)))
[void]$topBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90)))
[void]$topBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 70)))
[void]$topBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 60)))
$topBar.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 4)
$topBar.BackColor = $script:Surface

$targetBox = New-Object System.Windows.Forms.TextBox
$targetBox.Text = $Target
$targetBox.Dock = "Fill"
$targetBox.BorderStyle = "FixedSingle"

$shellBox = New-Object System.Windows.Forms.ComboBox
$shellBox.DropDownStyle = "DropDown"
foreach ($item in @("bash", "sh")) { [void]$shellBox.Items.Add($item) }
$shellBox.Text = $RemoteShell
$shellBox.Dock = "Fill"

$toolsBox = New-Object System.Windows.Forms.ComboBox
$toolsBox.DropDownStyle = "DropDown"
foreach ($item in @("linux,ssh,systemd,k8s,docker", "linux,ssh,systemd", "k8s,kubectl,helm", "docker,compose", "git", "python,pip,venv")) {
    [void]$toolsBox.Items.Add($item)
}
$toolsBox.Text = $Tools
$toolsBox.Dock = "Fill"

[void]$topBar.Controls.Add((New-Label "SSH"), 0, 0)
[void]$topBar.Controls.Add($targetBox, 1, 0)
[void]$topBar.Controls.Add((New-Label "Shell"), 2, 0)
[void]$topBar.Controls.Add($shellBox, 3, 0)
[void]$topBar.Controls.Add((New-Label (L '\u5de5\u5177')), 4, 0)
[void]$topBar.Controls.Add($toolsBox, 5, 0)

$terminal = New-Object System.Windows.Forms.RichTextBox
$terminal.Dock = "Fill"
$terminal.BackColor = $script:TerminalBg
$terminal.ForeColor = $script:TerminalFg
$terminal.Font = New-Object System.Drawing.Font("Consolas", 10)
$terminal.BorderStyle = "None"
$terminal.ReadOnly = $true
$terminal.WordWrap = $false
$terminal.ScrollBars = "Both"

$bottom = New-Object System.Windows.Forms.TableLayoutPanel
$bottom.Dock = "Fill"
$bottom.RowCount = 4
$bottom.ColumnCount = 1
[void]$bottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))
[void]$bottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
[void]$bottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$bottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
$bottom.BackColor = $script:Panel
$bottom.Padding = New-Object System.Windows.Forms.Padding(8)

$commandBox = New-Object System.Windows.Forms.TextBox
if ($Command) { $commandBox.Text = $Command } else { $commandBox.Text = "hostname && uptime && whoami" }
$commandBox.Dock = "Fill"
$commandBox.Font = New-Object System.Drawing.Font("Consolas", 10)

$quickButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$quickButtons.Dock = "Fill"
$quickButtons.BackColor = $script:Panel
$quickButtons.WrapContents = $false

$runButton = New-Button (L '\u6267\u884c\u8fdc\u7aef') 88
$testButton = New-Button (L '\u6d4b\u8bd5\u8fde\u63a5') 88
$explainButton = New-Button (L '\u89e3\u91ca\u547d\u4ee4') 88
$completeButton = New-Button (L 'AI \u8865\u5168') 88
$fixButton = New-Button (L '\u8bca\u65ad\u8f93\u51fa') 88
$toolsButton = New-Button (L '\u5de5\u5177\u83dc\u5355') 88
$linuxButton = New-Button (L 'Linux \u6392\u67e5') 88
$k8sButton = New-Button (L 'K8s \u670d\u52a1') 88
$copyButton = New-Button (L '\u590d\u5236\u8f93\u51fa') 88
$clearButton = New-Button (L '\u6e05\u7a7a') 72
$runButton.BackColor = $script:Accent
$runButton.ForeColor = [System.Drawing.Color]::White
foreach ($button in @($runButton, $testButton, $explainButton, $completeButton, $fixButton, $toolsButton, $linuxButton, $k8sButton, $copyButton, $clearButton)) {
    [void]$quickButtons.Controls.Add($button)
}

$hint = New-Object System.Windows.Forms.Label
$hint.Text = L '\u63d0\u793a\uff1a\u4e0a\u65b9\u662f\u8fdc\u7aef\u7ec8\u7aef\u8f93\u51fa\uff1b\u4e0b\u65b9\u8f93\u5165\u547d\u4ee4\u540e\u6267\u884c\u3002AI \u529f\u80fd\u4f1a\u8bfb\u53d6\u547d\u4ee4\u6216\u7ec8\u7aef\u8f93\u51fa\uff0c\u7ed3\u679c\u663e\u793a\u5728\u53f3\u4fa7\u3002'
$hint.Dock = "Fill"
$hint.ForeColor = $script:Muted
$hint.TextAlign = "MiddleLeft"

[void]$bottom.Controls.Add($commandBox, 0, 0)
[void]$bottom.Controls.Add($quickButtons, 0, 1)
[void]$bottom.Controls.Add($hint, 0, 2)

[void]$left.Controls.Add($topBar, 0, 0)
[void]$left.Controls.Add($terminal, 0, 1)
[void]$left.Controls.Add($bottom, 0, 2)

$right = New-Object System.Windows.Forms.TableLayoutPanel
$right.Dock = "Fill"
$right.RowCount = 3
$right.ColumnCount = 1
[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40)))
[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 72)))
[void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 28)))
$right.BackColor = $script:Surface
$right.Padding = New-Object System.Windows.Forms.Padding(8)

$aiTitle = New-Object System.Windows.Forms.Label
$aiTitle.Text = L 'AI \u8f93\u51fa / \u4efb\u52a1'
$aiTitle.Dock = "Fill"
$aiTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$aiTitle.ForeColor = $script:Fg

$aiBox = New-Object System.Windows.Forms.RichTextBox
$aiBox.Dock = "Fill"
$aiBox.BackColor = [System.Drawing.Color]::White
$aiBox.ForeColor = $script:Fg
$aiBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$aiBox.ReadOnly = $true
$aiBox.BorderStyle = "FixedSingle"
$aiBox.ScrollBars = "Vertical"

$taskBox = New-Object System.Windows.Forms.ListBox
$taskBox.Dock = "Fill"
$taskBox.BackColor = [System.Drawing.Color]::White
$taskBox.ForeColor = $script:Muted
$taskBox.BorderStyle = "FixedSingle"

[void]$right.Controls.Add($aiTitle, 0, 0)
[void]$right.Controls.Add($aiBox, 0, 1)
[void]$right.Controls.Add($taskBox, 0, 2)
[void]$main.Panel1.Controls.Add($left)
[void]$main.Panel2.Controls.Add($right)

$status = New-Object System.Windows.Forms.Label
$status.Text = L '\u5c31\u7eea'
$status.Dock = "Fill"
$status.TextAlign = "MiddleLeft"
$status.BackColor = $script:Surface
$status.ForeColor = $script:Muted

[void]$root.Controls.Add($title, 0, 0)
[void]$root.Controls.Add($main, 0, 1)
[void]$root.Controls.Add($status, 0, 2)
[void]$form.Controls.Add($root)

$runButton.Add_Click({ Start-RemoteCommand -TargetBox $targetBox -ShellBox $shellBox -CommandBox $commandBox -TerminalBox $terminal -StatusLabel $status -TaskBox $taskBox })
$commandBox.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; $runButton.PerformClick() } })
$testButton.Add_Click({ $commandBox.Text = "hostname && uptime && whoami"; $runButton.PerformClick() })
$explainButton.Add_Click({ Start-AiRequest -Mode "explain" -Text ([string]$commandBox.Text) -ToolsBox $toolsBox -AiBox $aiBox -StatusLabel $status -TaskBox $taskBox })
$completeButton.Add_Click({ Start-AiRequest -Mode "complete" -Text ([string]$commandBox.Text) -ToolsBox $toolsBox -AiBox $aiBox -StatusLabel $status -TaskBox $taskBox })
$fixButton.Add_Click({ Start-AiRequest -Mode "fix" -Text ([string]$terminal.Text) -ToolsBox $toolsBox -AiBox $aiBox -StatusLabel $status -TaskBox $taskBox })
$toolsButton.Add_Click({ Start-AiRequest -Mode "tools" -Text (L '\u751f\u6210\u8fdc\u7aef\u8fd0\u7ef4\u5e38\u7528\u547d\u4ee4\u83dc\u5355') -ToolsBox $toolsBox -AiBox $aiBox -StatusLabel $status -TaskBox $taskBox })
$linuxButton.Add_Click({ $commandBox.Text = "uname -a && uptime && df -h && free -h && ss -tulpen | head -40" })
$k8sButton.Add_Click({ $commandBox.Text = "kubectl get svc -A 2>/dev/null || kube get svc -A 2>/dev/null || echo 'kubectl/kube not found or kubeconfig unavailable'" })
$copyButton.Add_Click({ Set-Clipboard -Value $terminal.Text; $status.Text = L '\u7ec8\u7aef\u8f93\u51fa\u5df2\u590d\u5236' })
$clearButton.Add_Click({ $terminal.Clear(); $aiBox.Clear(); $taskBox.Items.Clear(); $status.Text = L '\u5df2\u6e05\u7a7a' })

[void]$form.ShowDialog()
