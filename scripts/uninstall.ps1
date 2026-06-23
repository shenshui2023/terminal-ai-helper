param(
    [switch]$KeepProfile,
    [switch]$KeepUserEnv,
    [switch]$KeepCache,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Say {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Text -ForegroundColor $Color
}

function Remove-PathIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($WhatIf) {
        Say "Would remove: $Path" Yellow
        return
    }
    Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue
    Say "Removed: $Path" Green
}

function Stop-Processes {
    $names = @("TerminalAi.Desktop")
    foreach ($name in $names) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            if ($WhatIf) {
                Say "Would stop process: $name $($process.Id)" Yellow
                continue
            }
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Say "Stopped process: $name $($process.Id)" Green
        }
    }
}

function Remove-StartupShortcuts {
    $startup = [Environment]::GetFolderPath("Startup")
    foreach ($name in @("TerminalAi.Desktop.lnk", "terminal-ai-helper-tray.lnk")) {
        Remove-PathIfExists -Path (Join-Path $startup $name)
    }
}

function Remove-ProfileLines {
    if ($KeepProfile) {
        Say "Keeping PowerShell profile entries." Yellow
        return
    }

    $profiles = @(
        $PROFILE.CurrentUserCurrentHost,
        $PROFILE.CurrentUserAllHosts
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($profilePath in $profiles) {
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }
        $content = Get-Content -LiteralPath $profilePath -Raw
        $lines = @($content -split "`r?`n")
        $filtered = New-Object System.Collections.Generic.List[string]
        $removed = $false
        foreach ($line in $lines) {
            if ($line -match 'terminal-ai-helper' -or $line -match [regex]::Escape($root)) {
                $removed = $true
                continue
            }
            $filtered.Add($line)
        }
        if (-not $removed) { continue }
        if ($WhatIf) {
            Say "Would update profile: $profilePath" Yellow
            continue
        }
        Set-Content -LiteralPath $profilePath -Value (($filtered -join "`r`n").TrimEnd() + "`r`n") -Encoding UTF8
        Say "Updated profile: $profilePath" Green
    }
}

function Remove-UserEnv {
    if ($KeepUserEnv) {
        Say "Keeping user environment variables." Yellow
        return
    }

    foreach ($name in @("TAIH_BASE_URL", "TAIH_MODEL", "TAIH_TIMEOUT_MS", "TAIH_TOOLS", "TAIH_PROXY", "TAIH_OUTPUT_STYLE", "TAIH_EXTRA_INSTRUCTIONS")) {
        $value = [Environment]::GetEnvironmentVariable($name, "User")
        if (-not $value) { continue }
        if ($WhatIf) {
            Say "Would remove user environment variable: $name" Yellow
            continue
        }
        [Environment]::SetEnvironmentVariable($name, $null, "User")
        [Environment]::SetEnvironmentVariable($name, $null, "Process")
        Say "Removed user environment variable: $name" Green
    }
}

function Remove-AppData {
    if ($KeepCache) {
        Say "Keeping cache and panel state." Yellow
        return
    }
    Remove-PathIfExists -Path (Join-Path $env:USERPROFILE ".terminal-ai-helper")
}

Say "Uninstalling terminal-ai-helper local integrations..." Cyan
Stop-Processes
Remove-StartupShortcuts
Remove-ProfileLines
Remove-UserEnv
Remove-AppData

Say ""
Say "Uninstall completed." Green
Say "Project source files are kept at: $root"
Say "To remove the project completely, delete that folder manually after closing related terminals."
