param(
    [switch]$Build
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$project = Join-Path $root "apps\desktop\TerminalAi.Desktop\TerminalAi.Desktop.csproj"

if ($Build) {
    dotnet build $project
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

dotnet run --project $project -- --root $root
