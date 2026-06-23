param(
    [string]$Prefix = "",
    [string]$Tools = "linux,ssh,systemd,k8s,docker,git",
    [string]$Style = "brief",
    [string]$Hint = "",
    [string]$PanelId = "",
    [long]$AnchorHandle = 0,
    [int]$AnchorX = -1,
    [int]$AnchorY = -1,
    [int]$AnchorW = -1,
    [int]$AnchorH = -1,
    [switch]$NoDialog,
    [switch]$WaitAi
)

$ErrorActionPreference = "Stop"
$script:TaihRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script:TaihCli = Join-Path $script:TaihRoot "bin\taih.js"

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

function Write-Result {
    param(
        [bool]$Ok,
        [string]$Completion = "",
        [string]$Source = "",
        [string]$ErrorText = ""
    )
    $obj = [ordered]@{
        ok = $Ok
        completion = $Completion
        source = $Source
    }
    if ($ErrorText) { $obj.error = $ErrorText }
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Output ($obj | ConvertTo-Json -Compress)
}

function Add-Candidate {
    param($List, [string]$Text)
    $value = ([string]$Text).Trim()
    if (-not $value) { return }
    if (-not $List.Contains($value)) {
        [void]$List.Add($value)
    }
}

function Convert-CompletionPrefix {
    param([string]$Text)
    $value = ([string]$Text).Trim()
    if (-not $value) { return "" }
    if ($value -eq "system") { return "systemctl" }
    if ($value -match '^system\s+(status|start|stop|restart|enable|disable|list|is-active|is-enabled)(\s+.*)?$') {
        return 'systemctl ' + $Matches[1] + $Matches[2]
    }
    if ($value -match '^system\s+(status|start|stop|restart|enable|disable|list|is-active|is-enabled)\S+$') {
        return 'systemctl ' + $Matches[1]
    }
    return $value
}

function Get-LocalCandidates {
    param([string]$Text)
    $trimmed = Convert-CompletionPrefix -Text $Text
    $list = New-Object System.Collections.Generic.List[string]
    if (-not $trimmed) { return @() }
    $command = ($trimmed -split '\s+', 2)[0].ToLowerInvariant()

    function Add-WhenUseful([string]$Candidate) {
        if ($Candidate.StartsWith($trimmed, [System.StringComparison]::OrdinalIgnoreCase) -or
            $trimmed -eq $command -or
            $Candidate.StartsWith("$trimmed ", [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Candidate $list $Candidate
        }
    }

    switch ($command) {
        "git" {
            @(
                "git status -sb",
                "git log --oneline -10",
                "git diff -- <file>",
                "git add <file>",
                "git commit -m `"<message>`"",
                "git push -u origin <branch>"
            ) | ForEach-Object { Add-WhenUseful $_ }
        }
        "ssh" {
            @(
                "ssh <user>@<host>",
                "ssh <user>@<host> -p <port>",
                "ssh -i <private-key> <user>@<host>",
                "ssh -R 17888:127.0.0.1:17888 <user>@<host>",
                "ssh -L <local-port>:127.0.0.1:<remote-port> <user>@<host>"
            ) | ForEach-Object { Add-WhenUseful $_ }
        }
        "docker" {
            @(
                "docker ps --format `"table {{.Names}}\t{{.Status}}\t{{.Ports}}`"",
                "docker logs -f <container>",
                "docker exec -it <container> sh",
                "docker compose up -d",
                "docker compose logs -f <service>"
            ) | ForEach-Object { Add-WhenUseful $_ }
        }
        "npm" {
            @("npm install", "npm run dev", "npm run build", "npm test", "npm outdated") |
                ForEach-Object { Add-WhenUseful $_ }
        }
        "python" {
            @("python -m venv .venv", "python -m pip install <package>", "python -m pytest", "python <script.py>") |
                ForEach-Object { Add-WhenUseful $_ }
        }
        "java" {
            @("java -version", "javac <file.java>", "java -jar <file.jar>") |
                ForEach-Object { Add-WhenUseful $_ }
        }
        "adb" {
            @("adb devices", "adb shell", "adb logcat", "adb install <app.apk>", "adb reverse tcp:<port> tcp:<port>") |
                ForEach-Object { Add-WhenUseful $_ }
        }
        { $_ -in @("kube", "kubectl") } {
            @(
                "$command get pods -A",
                "$command get svc -A",
                "$command get svc -n <namespace>",
                "$command get svc -n <namespace> -o wide",
                "$command get svc <service-name> -n <namespace> -o yaml",
                "$command describe svc <service-name> -n <namespace>",
                "$command get deploy -A",
                "$command logs -f <pod> -n <namespace>"
            ) | ForEach-Object { Add-WhenUseful $_ }
        }
        "systemctl" {
            @(
                "systemctl status <service>",
                "systemctl start <service>",
                "systemctl stop <service>",
                "systemctl restart <service>",
                "systemctl enable --now <service>",
                "systemctl list-units --type=service --state=running",
                "systemctl daemon-reload"
            ) | ForEach-Object { Add-WhenUseful $_ }
        }
        "systeminfo" {
            @("hostnamectl", "uname -a", "cat /etc/os-release", "lscpu", "free -h", "df -h") |
                ForEach-Object { Add-Candidate $list $_ }
        }
        "journalctl" {
            @(
                "journalctl -u <service> -n 100 --no-pager",
                "journalctl -u <service> -f",
                "journalctl -xe --no-pager"
            ) | ForEach-Object { Add-WhenUseful $_ }
        }
        "curl" {
            @(
                "curl -I <url>",
                "curl -sS <url>",
                "curl -sS -X POST <url> -H `"Content-Type: application/json`" -d '<json>'"
            ) | ForEach-Object { Add-WhenUseful $_ }
        }
        "ip" {
            @("ip addr", "ip route", "ip route get <ip>", "ip -br addr") |
                ForEach-Object { Add-WhenUseful $_ }
        }
        "ss" {
            @("ss -lntp", "ss -antp", "ss -lntp | grep <port>") |
                ForEach-Object { Add-WhenUseful $_ }
        }
    }

    if ($list.Count -eq 0 -and $trimmed.Length -ge 2) {
        Add-Candidate $list "$trimmed --help"
        Add-Candidate $list "$trimmed -h"
    }

    return @($list | Select-Object -First 8)
}

function Get-AiCandidatesFromFile {
    param([string]$StdoutFile)
    $items = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $StdoutFile)) { return @() }
    $raw = [System.IO.File]::ReadAllText($StdoutFile, [System.Text.Encoding]::UTF8).Trim()
    if (-not $raw) { return @() }
    $result = $raw | ConvertFrom-Json
    if ($result.completion) { Add-Candidate $items ([string]$result.completion) }
    if ($result.completions) {
        foreach ($item in @($result.completions)) { Add-Candidate $items ([string]$item) }
    }
    if ($result.examples) {
        foreach ($item in @($result.examples)) {
            if ($item.command) { Add-Candidate $items ([string]$item.command) }
        }
    }
    if ($result.related_commands) {
        foreach ($item in @($result.related_commands)) {
            if ($item.command) { Add-Candidate $items ([string]$item.command) }
        }
    }
    return @($items | Select-Object -First 10)
}

function Start-AiCompleteProcess {
    param([string]$Text, [string]$Toolset, [string]$OutputStyle, [string]$DirectionHint, [string]$StdoutFile, [string]$StderrFile, [switch]$ForceRefresh)
    $requestText = Convert-CompletionPrefix -Text $Text
    $args = @($script:TaihCli, "complete", "--json", "--tools", $Toolset, "--style", $OutputStyle)
    if ($ForceRefresh) { $args += "--no-cache" }
    $args += @("--", $requestText)
    if ($DirectionHint.Trim()) {
        $script:TaihPopupInstructionsFile = [System.IO.Path]::GetTempFileName()
        $hintInstruction = "Completion direction hint: $DirectionHint`nReturn more command candidates around this direction."
        [System.IO.File]::WriteAllText($script:TaihPopupInstructionsFile, $hintInstruction, [System.Text.Encoding]::UTF8)
        $args = @($script:TaihCli, "complete", "--json", "--tools", $Toolset, "--style", $OutputStyle)
        if ($ForceRefresh) { $args += "--no-cache" }
        $args += @("--instructions-file", $script:TaihPopupInstructionsFile, "--", $requestText)
    }
    $argumentLine = ($args | ForEach-Object { Q $_ }) -join " "
    return Start-Process -FilePath "node" -ArgumentList $argumentLine -RedirectStandardOutput $StdoutFile -RedirectStandardError $StderrFile -WindowStyle Hidden -PassThru
}

function Open-CompletionExplainPanel {
    param([string]$Text)
    $panelPath = Join-Path $script:TaihRoot "apps\powershell\panel.ps1"
    if (-not (Test-Path -LiteralPath $panelPath)) { return $false }
    $inputFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($inputFile, [string]$Text, [System.Text.Encoding]::UTF8)
    $targetPanelId = if ($PanelId) { $PanelId } else { "completion-popup" }
    Start-Process -FilePath "powershell" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $panelPath,
        "-InputFile", $inputFile,
        "-Mode", "explain",
        "-PanelId", $targetPanelId,
        "-AnchorHandle", [string]$AnchorHandle,
        "-AnchorX", [string]$AnchorX,
        "-AnchorY", [string]$AnchorY,
        "-AnchorW", [string]$AnchorW,
        "-AnchorH", [string]$AnchorH
    ) -WindowStyle Hidden | Out-Null
    return $true
}

$local = @(Get-LocalCandidates -Text $Prefix)
if ($NoDialog) {
    $choice = if ($local.Count -gt 0) { [string]$local[0] } else { $Prefix }
    if ($WaitAi) {
        $stdout = [System.IO.Path]::GetTempFileName()
        $stderr = [System.IO.Path]::GetTempFileName()
        $script:TaihPopupInstructionsFile = $null
        $aiProcess = $null
        try {
            $aiProcess = Start-AiCompleteProcess -Text $Prefix -Toolset $Tools -OutputStyle $Style -DirectionHint $Hint -StdoutFile $stdout -StderrFile $stderr
            $aiProcess.WaitForExit()
            $items = @(Get-AiCandidatesFromFile -StdoutFile $stdout)
            if ($items.Count -gt 0) {
                Write-Result -Ok $true -Completion ([string]$items[0]) -Source "ai"
                exit 0
            }
            $err = ""
            try { $err = [System.IO.File]::ReadAllText($stderr, [System.Text.Encoding]::UTF8).Trim() } catch {}
            if ($aiProcess.ExitCode -ne 0) {
                Write-Result -Ok $false -Completion $choice -Source "local" -ErrorText $err
                exit 1
            }
        } finally {
            Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
            if ($script:TaihPopupInstructionsFile) { Remove-Item -LiteralPath $script:TaihPopupInstructionsFile -Force -ErrorAction SilentlyContinue }
            if ($aiProcess) { try { $aiProcess.Dispose() } catch {} }
        }
    }
    Write-Result -Ok $true -Completion $choice -Source "local"
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$bg = [System.Drawing.Color]::FromArgb(18, 18, 18)
$surface = [System.Drawing.Color]::FromArgb(31, 31, 31)
$fg = [System.Drawing.Color]::FromArgb(235, 235, 235)
$muted = [System.Drawing.Color]::FromArgb(155, 155, 155)
$accent = [System.Drawing.Color]::FromArgb(0, 122, 204)

$form = New-Object System.Windows.Forms.Form
$form.Text = L '\u667a\u80fd\u8865\u5168'
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "None"
$form.ShowInTaskbar = $true
$form.TopMost = $true
$form.BackColor = $bg
$form.ForeColor = $fg
$form.Size = New-Object System.Drawing.Size(760, 250)
$form.KeyPreview = $true

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = "Fill"
$root.RowCount = 4
$root.ColumnCount = 1
$root.Padding = New-Object System.Windows.Forms.Padding(8)
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 32)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))

$hint = New-Object System.Windows.Forms.Label
$hint.Text = L '\u672c\u5730\u5019\u9009\u5148\u663e\u793a\uff0cAI \u5019\u9009\u540e\u53f0\u8ffd\u52a0\u3002Enter \u63d2\u5165\uff0cCtrl+E/F1 \u89e3\u91ca\uff0cEsc \u53d6\u6d88\u3002'
$hint.Dock = "Fill"
$hint.ForeColor = $muted
$hint.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

$list = New-Object System.Windows.Forms.ListBox
$list.Dock = "Fill"
$list.BackColor = $surface
$list.ForeColor = $fg
$list.BorderStyle = "None"
$list.Font = New-Object System.Drawing.Font("Consolas", 10)

$edit = New-Object System.Windows.Forms.TextBox
$edit.Dock = "Fill"
$edit.BackColor = [System.Drawing.Color]::Black
$edit.ForeColor = $fg
$edit.BorderStyle = "None"
$edit.Font = New-Object System.Drawing.Font("Consolas", 10)

$bottom = New-Object System.Windows.Forms.FlowLayoutPanel
$bottom.Dock = "Fill"
$bottom.FlowDirection = "RightToLeft"
$bottom.BackColor = $bg

function New-Button([string]$Text, [int]$Width = 82) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 28
    $button.FlatStyle = "Flat"
    $button.BackColor = $surface
    $button.ForeColor = $fg
    $button.Margin = New-Object System.Windows.Forms.Padding(5, 2, 0, 2)
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(78, 78, 78)
    return $button
}

$insert = New-Button (L '\u63d2\u5165')
$insert.BackColor = $accent
$refresh = New-Button (L '\u5237\u65b0AI') 88
$explain = New-Button (L '\u89e3\u91ca')
$copy = New-Button (L '\u590d\u5236')
$close = New-Button (L '\u53d6\u6d88')
$status = New-Object System.Windows.Forms.Label
$status.AutoSize = $true
$status.ForeColor = $muted
$status.Padding = New-Object System.Windows.Forms.Padding(0, 7, 12, 0)
$status.Text = L 'AI \u6b63\u5728\u540e\u53f0\u8865\u5145...'

[void]$bottom.Controls.Add($close)
[void]$bottom.Controls.Add($copy)
[void]$bottom.Controls.Add($explain)
[void]$bottom.Controls.Add($refresh)
[void]$bottom.Controls.Add($insert)
[void]$bottom.Controls.Add($status)
[void]$root.Controls.Add($hint, 0, 0)
[void]$root.Controls.Add($list, 0, 1)
[void]$root.Controls.Add($edit, 0, 2)
[void]$root.Controls.Add($bottom, 0, 3)
[void]$form.Controls.Add($root)

foreach ($item in $local) { Add-Candidate $list.Items $item }
if ($list.Items.Count -eq 0 -and $Prefix.Trim()) { Add-Candidate $list.Items $Prefix }
if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0; $edit.Text = [string]$list.SelectedItem }
$edit.SelectionStart = $edit.TextLength

$script:choice = $null
$script:choiceSource = "local"
$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
$process = $null
$script:TaihPopupInstructionsFile = $null

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 180
$timer.Add_Tick({
    if (-not $process) { return }
    if (-not $process.HasExited) { return }
    $timer.Stop()
    try {
        $before = $list.Items.Count
        foreach ($item in (Get-AiCandidatesFromFile -StdoutFile $stdoutFile)) {
            Add-Candidate $list.Items $item
        }
        $added = $list.Items.Count - $before
        if ($added -gt 0) {
            $status.Text = (L 'AI \u5019\u9009\u5df2\u52a0\u5165\uff1a') + $added
            $script:choiceSource = "ai"
            if ($WaitAi) {
                $list.SelectedIndex = $before
                $edit.Text = [string]$list.SelectedItem
                $script:choice = [string]$edit.Text
                $form.Close()
            }
            return
        }
        $err = ""
        try { $err = [System.IO.File]::ReadAllText($stderrFile, [System.Text.Encoding]::UTF8).Trim() } catch {}
        if ($process.ExitCode -ne 0) {
            if ($err.Length -gt 120) { $err = $err.Substring(0, 120) + "..." }
            $status.Text = (L 'AI \u5019\u9009\u5931\u8d25\uff0c\u5df2\u4fdd\u7559\u672c\u5730\u5019\u9009') + $(if ($err) { ": $err" } else { "" })
        } else {
            $status.Text = L 'AI \u672a\u8fd4\u56de\u65b0\u5019\u9009'
        }
        if ($WaitAi) {
            $script:choice = [string]$edit.Text
            $form.Close()
        }
    } catch {
        $status.Text = (L 'AI \u5019\u9009\u89e3\u6790\u5931\u8d25\uff1a') + $_.Exception.Message
        if ($WaitAi) {
            $script:choice = [string]$edit.Text
            $form.Close()
        }
    } finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
        if ($script:TaihPopupInstructionsFile) { Remove-Item -LiteralPath $script:TaihPopupInstructionsFile -Force -ErrorAction SilentlyContinue }
        try { $process.Dispose() } catch {}
        $process = $null
    }
})

$startAi = {
    param([switch]$ForceRefresh)
    if ($process -and -not $process.HasExited) {
        try { $process.Kill() } catch {}
    }
    Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    if ($script:TaihPopupInstructionsFile) {
        Remove-Item -LiteralPath $script:TaihPopupInstructionsFile -Force -ErrorAction SilentlyContinue
        $script:TaihPopupInstructionsFile = $null
    }
    try {
        $process = Start-AiCompleteProcess -Text $Prefix -Toolset $Tools -OutputStyle $Style -DirectionHint $Hint -StdoutFile $stdoutFile -StderrFile $stderrFile -ForceRefresh:$ForceRefresh
        $status.Text = if ($ForceRefresh) { L 'AI \u6b63\u5728\u5237\u65b0\u5019\u9009\u5e76\u66f4\u65b0\u7f13\u5b58...' } else { L 'AI \u6b63\u5728\u8bfb\u53d6\u7f13\u5b58\u6216\u540e\u53f0\u8865\u5145...' }
        $timer.Start()
    } catch {
        $status.Text = (L 'AI \u5019\u9009\u542f\u52a8\u5931\u8d25\uff1a') + $_.Exception.Message
        if ($WaitAi) {
            $script:choice = [string]$edit.Text
            $form.Close()
        }
    }
}

$form.Add_Shown({ & $startAi })

$list.Add_SelectedIndexChanged({
    if ($list.SelectedIndex -ge 0) {
        $edit.Text = [string]$list.SelectedItem
        $edit.SelectionStart = $edit.TextLength
    }
})

$accept = {
    $value = ([string]$edit.Text).Trim()
    if ($value) {
        $script:choice = $value
        $form.Close()
    }
}

$insert.Add_Click($accept)
$list.Add_DoubleClick($accept)
$refresh.Add_Click({ & $startAi -ForceRefresh })
$copy.Add_Click({
    if ($edit.Text) {
        Set-Clipboard -Value $edit.Text
        $status.Text = L '\u5df2\u590d\u5236'
    }
})
$explain.Add_Click({
    $value = ([string]$edit.Text).Trim()
    if ($value) {
        [void](Open-CompletionExplainPanel -Text $value)
        $script:choice = $null
        $script:choiceSource = "cancelled"
        $form.Close()
    }
})
$close.Add_Click({ $form.Close() })
$form.Add_KeyDown({
    if ($_.KeyCode -eq "Escape") { $form.Close() }
    elseif ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; & $accept }
    elseif ($_.KeyCode -eq "F1" -or ($_.Control -and $_.KeyCode -eq "E")) {
        $_.SuppressKeyPress = $true
        $explain.PerformClick()
    }
})
$form.Add_FormClosed({
    try { $timer.Stop(); $timer.Dispose() } catch {}
    if ($process -and -not $process.HasExited) { try { $process.Kill() } catch {} }
    Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    if ($script:TaihPopupInstructionsFile) { Remove-Item -LiteralPath $script:TaihPopupInstructionsFile -Force -ErrorAction SilentlyContinue }
})

[void]$form.ShowDialog()

if ($script:choice) {
    Write-Result -Ok $true -Completion $script:choice -Source $script:choiceSource
} else {
    Write-Result -Ok $false -Source "cancelled" -ErrorText "cancelled"
}
