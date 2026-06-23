$script:TaihDesktopMaxTextLength = 40000

function Ensure-TerminalAiDesktopNative {
    if ("TaihDesktopWin32" -as [type]) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TaihDesktopWin32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
}
"@
}

function Ensure-TerminalAiUiAutomation {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
}

function Get-TerminalAiForegroundWindowHandle {
    Ensure-TerminalAiDesktopNative
    return [TaihDesktopWin32]::GetForegroundWindow()
}

function Convert-TerminalAiScreenLineToCommand {
    param([AllowNull()][string]$Line)

    $value = ([string]$Line) -replace "`0", ""
    $value = $value.Trim()
    if (-not $value) { return "" }

    $patterns = @(
        '^(?:\([^)]+\)\s*)?PS\s+[^>]*>\s*(.+)$',
        '^[A-Za-z]:\\[^>]*>\s*(.+)$',
        '^\[[^\]]+\]\s*[#$]\s*(.+)$',
        '^[^@\s]+@[^:\s]+:[^#$]*[#$]\s*(.+)$',
        '^[#$]\s*(.+)$'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($value, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }

    return $value
}

function Get-TerminalAiCommandFromScreenText {
    param([AllowNull()][string]$Text)

    $value = ([string]$Text) -replace "`0", ""
    if (-not $value.Trim()) { return "" }

    $lines = @($value -split "`r?`n" | ForEach-Object { ([string]$_).TrimEnd() } | Where-Object { $_.Trim() })
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        $candidate = Convert-TerminalAiScreenLineToCommand -Line $lines[$index]
        if ($candidate) { return $candidate }
    }

    return ""
}

function Get-TerminalAiTextPatternText {
    param($Element)

    try {
        $pattern = $Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if ($pattern) {
            return $pattern.DocumentRange.GetText($script:TaihDesktopMaxTextLength)
        }
    } catch {
        return ""
    }
    return ""
}

function Get-TerminalAiValuePatternText {
    param($Element)

    try {
        $pattern = $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($pattern) {
            return [string]$pattern.Current.Value
        }
    } catch {
        return ""
    }
    return ""
}

function Get-TerminalAiVisibleTerminalText {
    param([IntPtr]$Handle)

    Ensure-TerminalAiUiAutomation
    if ($Handle -eq [IntPtr]::Zero) { return "" }

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($Handle)
    if (-not $root) { return "" }

    $texts = New-Object System.Collections.Generic.List[string]
    foreach ($text in @((Get-TerminalAiTextPatternText -Element $root), (Get-TerminalAiValuePatternText -Element $root), [string]$root.Current.Name)) {
        if ($text -and $text.Trim()) { $texts.Add($text) }
    }

    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $all) {
        foreach ($text in @((Get-TerminalAiTextPatternText -Element $element), (Get-TerminalAiValuePatternText -Element $element), [string]$element.Current.Name)) {
            if ($text -and $text.Trim() -and $text.Length -gt 2) {
                $texts.Add($text)
            }
        }
    }

    if ($texts.Count -eq 0) { return "" }
    return @($texts | Sort-Object Length -Descending | Select-Object -First 1)[0]
}

function Get-TerminalAiForegroundTerminalContext {
    $handle = Get-TerminalAiForegroundWindowHandle
    $text = ""
    $command = ""
    $errorText = ""

    try {
        $text = Get-TerminalAiVisibleTerminalText -Handle $handle
        $command = Get-TerminalAiCommandFromScreenText -Text $text
    } catch {
        $errorText = $_.Exception.Message
    }

    return [pscustomobject]@{
        Handle = $handle
        Text = $text
        Command = $command
        CommandLength = $command.Length
        Error = $errorText
    }
}

function Send-TerminalAiBackspace {
    param([int]$Count)

    if ($Count -le 0) { return }
    $remaining = $Count
    while ($remaining -gt 0) {
        $chunk = [Math]::Min($remaining, 60)
        [System.Windows.Forms.SendKeys]::SendWait("{BACKSPACE $chunk}")
        Start-Sleep -Milliseconds 20
        $remaining -= $chunk
    }
}

function Send-TerminalAiTextToWindow {
    param(
        [IntPtr]$Handle,
        [string]$Text,
        [string]$ExistingText = "",
        [switch]$ClearLine
    )

    Ensure-TerminalAiDesktopNative
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    if ($Handle -eq [IntPtr]::Zero -or -not [TaihDesktopWin32]::IsWindow($Handle)) {
        throw "target window is not available"
    }

    $oldClipboard = ""
    try { $oldClipboard = Get-Clipboard -Raw -ErrorAction SilentlyContinue } catch {}
    [void][TaihDesktopWin32]::SetForegroundWindow($Handle)
    Start-Sleep -Milliseconds 120
    if ($ClearLine) {
        [System.Windows.Forms.SendKeys]::SendWait("{END}")
        Start-Sleep -Milliseconds 60
        $deleteCount = if ($ExistingText) { $ExistingText.Length } else { 240 }
        Send-TerminalAiBackspace -Count $deleteCount
        Start-Sleep -Milliseconds 60
    }
    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 80
    [System.Windows.Forms.SendKeys]::SendWait("^v")
    Start-Sleep -Milliseconds 160
    if ($oldClipboard) {
        try { Set-Clipboard -Value $oldClipboard } catch {}
    }
}
