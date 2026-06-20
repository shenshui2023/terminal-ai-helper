@echo off
setlocal
set "TAIH_ROOT=%~dp0"
set "TAIH_CWD=%CD%"
powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -Command ". '%TAIH_ROOT%powershell\taih-profile.ps1'; Set-Location -LiteralPath '%TAIH_CWD%'"
