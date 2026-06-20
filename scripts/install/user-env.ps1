param(
    [string]$BaseUrl = "https://qyapi.cjyyswq.com",
    [string]$Model = "gpt-5.5"
)

Write-Host "Configuring terminal-ai-helper user environment variables." -ForegroundColor Cyan
Write-Host "The API key will be stored in the current Windows user's OPENAI_API_KEY environment variable." -ForegroundColor DarkGray
Write-Host "It will not be written into the project source code." -ForegroundColor DarkGray

$secure = Read-Host "Enter API key" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)

    if (-not $plain) {
        throw "API key is empty. Cancelled."
    }

    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $plain, "User")
    [Environment]::SetEnvironmentVariable("TAIH_BASE_URL", $BaseUrl, "User")
    [Environment]::SetEnvironmentVariable("TAIH_MODEL", $Model, "User")

    Write-Host "Done. Restart PowerShell, then run:" -ForegroundColor Green
    $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    Write-Host "  node $root\bin\taih.js doctor"
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
