param(
    [switch]$SkipQdrant
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AiDir = Split-Path -Parent $ScriptDir
$ComposeFile = Join-Path $AiDir "docker-compose.ai.yml"
$QdrantStorage = Join-Path $AiDir "qdrant_storage"

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Quiet
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($output -and -not $Quiet) {
        $output | ForEach-Object { Write-Host $_ }
    }
    if ($exitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed with exit code $exitCode"
    }
}

function Wait-HttpEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$Attempts = 30,
        [int]$DelaySeconds = 2
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            return Invoke-RestMethod -Uri $Url -TimeoutSec 3
        } catch {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    throw "Endpoint did not become reachable: $Url"
}

if (-not $SkipQdrant) {
    if (-not (Test-CommandExists "docker")) {
        throw "Docker CLI was not found in PATH."
    }

    New-Item -ItemType Directory -Path $QdrantStorage -Force | Out-Null

    Invoke-NativeCommand -FilePath "docker" -Arguments @("info") -Quiet
    Invoke-NativeCommand -FilePath "docker" -Arguments @("compose", "-f", $ComposeFile, "up", "-d", "qdrant")

    $qdrant = Wait-HttpEndpoint -Url "http://localhost:6333/"
    Write-Host "Qdrant is reachable at http://localhost:6333"
    if ($qdrant.version) {
        Write-Host "Qdrant version: $($qdrant.version)"
    }
}

$LightRagEnv = Join-Path $AiDir "lightrag\.env"
if (Test-Path -LiteralPath $LightRagEnv) {
    Write-Host "LightRAG .env exists. Start LightRAG manually from .ai/lightrag after installing uv/lightrag-hku."
} else {
    Write-Host "LightRAG is prepared but not started. Copy .ai/lightrag/.env.example to .env first."
}
