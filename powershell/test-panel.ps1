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
foreach ($key in @("Alt+/", "Alt+?", "Alt+C", "Alt+F", "Ctrl+Spacebar", "F2", "F3", "F4", "F8")) {
    if ($boundKeys -notcontains $key) {
        throw "missing hotkey: $key"
    }
}
foreach ($aliasName in @("taih-current", "taih-popup", "taih-panel", "taih-clip", "taih-fix", "taih-keys", "taih-what-key", "taih-complete-popup", "taih-complete-stable", "taih-panel-reset")) {
    if (-not (Get-Alias $aliasName -ErrorAction SilentlyContinue)) {
        throw "missing alias: $aliasName"
    }
}

Write-Host "test: local completion candidates are available"
$localCompletions = @(Get-TerminalAiLocalCompletions -Prefix "git st")
if (-not ($localCompletions | Where-Object { $_ -like "git status*" })) {
    throw "missing local git status completion"
}
$sshCandidate = (L '\u003c\u7528\u6237\u540d\u003e') + "@" + (L '\u003c\u4e3b\u673a\u003e')
$sshCompletions = @(Get-TerminalAiLocalCompletions -Prefix "ssh")
if (-not ($sshCompletions | Where-Object { $_ -like "ssh *$sshCandidate*" })) {
    throw "missing readable ssh completion candidate"
}
$kubeCompletions = @(Get-TerminalAiLocalCompletions -Prefix "kube get svc")
if ($kubeCompletions.Count -lt 3 -or -not ($kubeCompletions | Where-Object { $_ -like "kube get svc -A" })) {
    throw "missing local Kubernetes service completion candidates"
}

Write-Host "test: completion popup can render local candidates without API"
$env:TAIH_TEST_NO_AI_COMPLETION = "1"
$env:TAIH_TEST_COMPLETION_POPUP_NO_DIALOG = "1"
try {
    $choice = Show-TerminalAiCompletionPopup -Prefix "ssh"
    if ($choice -notlike "ssh *$sshCandidate*") {
        throw "completion popup did not return a readable local ssh candidate: $choice"
    }
} finally {
    Remove-Item Env:\TAIH_TEST_NO_AI_COMPLETION -ErrorAction SilentlyContinue
    Remove-Item Env:\TAIH_TEST_COMPLETION_POPUP_NO_DIALOG -ErrorAction SilentlyContinue
}

Write-Host "test: AI completion schema can carry multiple candidates"
$apiPath = Join-Path $root "src\api.js"
$promptPath = Join-Path $root "src\prompts.js"
$apiSource = Get-Content -LiteralPath $apiPath -Raw
$promptSource = Get-Content -LiteralPath $promptPath -Raw
if ($apiSource -notmatch "completions") {
    throw "API normalization does not include completions array"
}
if ($promptSource -notmatch "complete" -or $promptSource -notmatch "--help") {
    throw "prompt does not ask for multiple AI completion candidates"
}
if ($apiSource -notmatch 'input: `\$\{prompt\.system\}\\n\\n\$\{prompt\.user\}`') {
    throw "structured JSON request must use single string input for qyapi compatibility"
}

Write-Host "test: completion popup handles AI process and explain action"
$profileSource = Get-Content -LiteralPath $profilePath -Raw
if ($profileSource -notmatch '\$process\.WaitForExit\(\)') {
    throw "completion popup must wait for the AI process before checking ExitCode"
}
if ($profileSource -notmatch '\$explain = New-CompletionButton' -or $profileSource -notmatch 'Show-TerminalAiPanel -InitialText \$value -Mode explain') {
    throw "completion popup is missing the explain action"
}
if ($profileSource -notmatch 'Show-TerminalAiPanel -InitialText \$value -Mode explain[\s\S]{0,160}\$form\.Close\(\)') {
    throw "completion popup explain action must close the modal popup"
}
if ($profileSource -notmatch '\$form\.FormBorderStyle = "None"' -or $profileSource -notmatch '\$form\.Add_Deactivate') {
    throw "completion popup must be borderless and close when focus leaves"
}
if ($profileSource -notmatch 'if \(\$added -gt 0\)' -or $profileSource -notmatch 'exit=\$\(\$process\.ExitCode\)') {
    throw "completion popup should prefer parsed AI candidates before reporting process errors"
}

$panelSource = Get-Content -LiteralPath $panelPath -Raw
if ($panelSource -notmatch '\$form\.FormBorderStyle = "None"') {
    throw "manager panel should use a borderless terminal-like shell"
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

Write-Host "test: panel process stays alive"
$panelInput = [System.IO.Path]::GetTempFileName()
$panelOut = [System.IO.Path]::GetTempFileName()
$panelErr = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($panelInput, "", [System.Text.Encoding]::UTF8)
$panelProcess = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $panelPath,
        "-InputFile", $panelInput,
        "-Mode", "explain",
        "-PanelId", "test-panel-smoke",
        "-AnchorX", "-1",
        "-AnchorY", "-1",
        "-AnchorW", "-1",
        "-AnchorH", "-1"
    ) `
    -RedirectStandardOutput $panelOut `
    -RedirectStandardError $panelErr `
    -WindowStyle Hidden `
    -PassThru
try {
    Start-Sleep -Seconds 2
    if ($panelProcess.HasExited) {
        $stderr = ""
        try { $stderr = Get-Content -LiteralPath $panelErr -Raw -ErrorAction SilentlyContinue } catch {}
        throw "panel process exited during smoke test: $stderr"
    }
} finally {
    if ($panelProcess -and -not $panelProcess.HasExited) {
        Stop-Process -Id $panelProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $panelInput, $panelOut, $panelErr -Force -ErrorAction SilentlyContinue
    $smokeDir = Join-Path $env:USERPROFILE ".terminal-ai-helper\panels"
    Remove-Item -Path (Join-Path $smokeDir "test-panel-smoke.*") -Force -ErrorAction SilentlyContinue
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
