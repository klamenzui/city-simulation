$ErrorActionPreference = "Continue"

$ProjectRoot = "C:\dev\projects\Godot\city-simulation"
$VaultPath = "C:\dev\projects\ai_brain"
$CodexConfigUser = Join-Path $HOME ".codex\config.toml"
$CodexConfigProject = Join-Path $ProjectRoot ".codex\config.toml"

function Get-VersionLine {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @("--version")
    )

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return $null
    }

    try {
        return (& $cmd.Source @Arguments 2>&1 | Select-Object -First 3) -join " "
    } catch {
        return $_.Exception.Message
    }
}

function Get-VersionLineFromPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @("--version")
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return (& $Path @Arguments 2>&1 | Select-Object -First 3) -join " "
    } catch {
        return $_.Exception.Message
    }
}

function Select-FirstValue {
    param(
        [AllowNull()][object]$Primary,
        [AllowNull()][object]$Fallback
    )

    if ($null -ne $Primary -and "$Primary" -ne "") {
        return $Primary
    }
    return $Fallback
}

function Test-Http {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        return [ordered]@{ ok = $true; status = [int]$response.StatusCode }
    } catch {
        return [ordered]@{ ok = $false; error = $_.Exception.Message }
    }
}

$markdownCount = 0
if (Test-Path -LiteralPath $VaultPath -PathType Container) {
    $markdownCount = @(
        Get-ChildItem -LiteralPath $VaultPath -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch "\\.obsidian(\\|$)" }
    ).Count
}

$result = [ordered]@{
    projectRoot = $ProjectRoot
    projectConfigExists = Test-Path -LiteralPath $CodexConfigProject -PathType Leaf
    userConfigExists = Test-Path -LiteralPath $CodexConfigUser -PathType Leaf
    vaultExists = Test-Path -LiteralPath $VaultPath -PathType Container
    vaultMarkdownFilesExcludingObsidian = $markdownCount
    tools = [ordered]@{
        codex = Get-VersionLine "codex"
        node = Get-VersionLine "node"
        npm = Get-VersionLine "npm.cmd"
        npx = Get-VersionLine "npx.cmd"
        python = Get-VersionLine "python"
        py = Get-VersionLine "py"
        uv = Select-FirstValue (Get-VersionLine "uv") (Get-VersionLineFromPath "C:\Users\klame\AppData\Roaming\Python\Python313\Scripts\uv.exe")
        uvx = Select-FirstValue (Get-VersionLine "uvx") (Get-VersionLineFromPath "C:\Users\klame\AppData\Roaming\Python\Python313\Scripts\uvx.exe")
        docker = Get-VersionLine "docker"
    }
    endpoints = [ordered]@{
        qdrant = Test-Http "http://localhost:6333/"
        lightrag = Test-Http "http://localhost:9621/health"
        obsidianLocalRestHttp = Test-Http "http://127.0.0.1:27123"
        obsidianLocalRestHttps = Test-Http "https://127.0.0.1:27124"
    }
}

$result | ConvertTo-Json -Depth 6
