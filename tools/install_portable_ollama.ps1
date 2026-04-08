param(
	[string]$ProjectRoot = "",
	[string]$RuntimeDir = "",
	[string]$ModelsDir = "",
	[string]$RuntimeStateDir = "",
	[string]$Model = "qwen2.5:3b",
	[string]$ReleaseTag = "",
	[switch]$SkipModelPull
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
	$ProjectRoot = Split-Path -Parent $PSScriptRoot
}
if (-not $RuntimeDir) {
	$RuntimeDir = Join-Path $ProjectRoot "AI\llama"
}
if (-not $ModelsDir) {
	$ModelsDir = Join-Path $ProjectRoot "AI\models"
}
if (-not $RuntimeStateDir) {
	$RuntimeStateDir = Join-Path $ProjectRoot "AI\runtime"
}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null
New-Item -ItemType Directory -Force -Path $RuntimeStateDir | Out-Null

$ollamaExe = Get-ChildItem -Path $RuntimeDir -Filter "ollama.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $ollamaExe) {
	$releaseApi = if ($ReleaseTag) {
		"https://api.github.com/repos/ollama/ollama/releases/tags/$ReleaseTag"
	} else {
		"https://api.github.com/repos/ollama/ollama/releases/latest"
	}

	Write-Host "Fetching Ollama release metadata from $releaseApi"
	$release = Invoke-RestMethod -Uri $releaseApi -Headers @{ "User-Agent" = "city-simulation-setup" }
	$asset = $release.assets | Where-Object { $_.name -eq "ollama-windows-amd64.zip" } | Select-Object -First 1
	if ($null -eq $asset) {
		throw "Could not find asset 'ollama-windows-amd64.zip' in release metadata."
	}

	$zipPath = Join-Path $RuntimeStateDir $asset.name
	Write-Host "Downloading $($asset.browser_download_url) to $zipPath"
	Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath

	Write-Host "Extracting runtime to $RuntimeDir"
	Expand-Archive -Path $zipPath -DestinationPath $RuntimeDir -Force

	$ollamaExe = Get-ChildItem -Path $RuntimeDir -Filter "ollama.exe" -Recurse | Select-Object -First 1
	if ($null -eq $ollamaExe) {
		throw "ollama.exe was not found after extraction."
	}
}
else {
	Write-Host "Using existing local runtime at $($ollamaExe.FullName)"
}

$env:OLLAMA_MODELS = $ModelsDir
$env:OLLAMA_HOST = "127.0.0.1:11434"

$healthUrl = "http://127.0.0.1:11434/api/version"
$backendReady = $false
try {
	Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 | Out-Null
	$backendReady = $true
	Write-Host "Ollama backend already reachable on 127.0.0.1:11434"
}
catch {
	Write-Host "Starting local Ollama backend from $($ollamaExe.FullName)"
	$process = Start-Process -FilePath $ollamaExe.FullName -ArgumentList "serve" -WorkingDirectory $RuntimeDir -WindowStyle Hidden -PassThru
	for ($i = 0; $i -lt 30; $i++) {
		Start-Sleep -Seconds 1
		try {
			Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 | Out-Null
			$backendReady = $true
			break
		}
		catch {
		}
	}
	if (-not $backendReady) {
		throw "Local Ollama backend did not become ready in time."
	}
	Write-Host "Local Ollama backend started with PID $($process.Id)"
}

if (-not $SkipModelPull) {
	Write-Host "Pulling model $Model into $ModelsDir"
	& $ollamaExe.FullName pull $Model
	if ($LASTEXITCODE -ne 0) {
		throw "Model pull failed for $Model"
	}
}

Write-Host ""
Write-Host "Portable Ollama setup complete."
Write-Host "Runtime: $($ollamaExe.FullName)"
Write-Host "Models:  $ModelsDir"
if (-not $SkipModelPull) {
	Write-Host "Model:   $Model"
}
