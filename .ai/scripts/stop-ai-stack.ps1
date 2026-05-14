$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AiDir = Split-Path -Parent $ScriptDir
$ComposeFile = Join-Path $AiDir "docker-compose.ai.yml"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI was not found in PATH."
}

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $output = docker compose -f $ComposeFile down 2>&1
    $exitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousPreference
}
if ($output) {
    $output | ForEach-Object { Write-Host $_ }
}
if ($exitCode -ne 0) {
    throw "docker compose down failed with exit code $exitCode"
}

Write-Host "AI stack containers stopped."
