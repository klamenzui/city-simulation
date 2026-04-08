param(
	[string]$ProjectRoot = "",
	[string]$RuntimeDir = "",
	[string]$ModelsDir = "",
	[string]$BaseModel = "qwen2.5:3b",
	[string]$PlayerProfileName = "npc-player",
	[string]$NpcProfileName = "npc-overheard"
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

$profilesDir = Join-Path $ProjectRoot "AI\profiles"
$runtimeStateDir = Join-Path $ProjectRoot "AI\runtime"
$generatedDir = Join-Path $runtimeStateDir "generated_profiles"
$ollamaExe = Join-Path $RuntimeDir "ollama.exe"

if (-not (Test-Path $ollamaExe)) {
	throw "Could not find ollama.exe at $ollamaExe"
}
if (-not (Test-Path $profilesDir)) {
	throw "Could not find profile templates at $profilesDir"
}

New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null

$env:OLLAMA_MODELS = $ModelsDir
$env:OLLAMA_HOST = "127.0.0.1:11434"

$healthUrl = "http://127.0.0.1:11434/api/version"
$backendReady = $false
try {
	Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 | Out-Null
	$backendReady = $true
}
catch {
	$process = Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WorkingDirectory $RuntimeDir -WindowStyle Hidden -PassThru
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
	Write-Host "Started local Ollama backend with PID $($process.Id)"
}

function New-GeneratedModelfile {
	param(
		[string]$TemplateName,
		[string]$TargetName
	)

	$templatePath = Join-Path $profilesDir $TemplateName
	if (-not (Test-Path $templatePath)) {
		throw "Template missing: $templatePath"
	}
	$targetPath = Join-Path $generatedDir $TargetName
	$content = Get-Content -Path $templatePath -Raw
	$content = $content.Replace("{{BASE_MODEL}}", $BaseModel)
	Set-Content -Path $targetPath -Value $content -Encoding UTF8
	return $targetPath
}

$playerModelfile = New-GeneratedModelfile -TemplateName "player_npc.Modelfile.in" -TargetName "npc-player.Modelfile"
$npcModelfile = New-GeneratedModelfile -TemplateName "npc_npc.Modelfile.in" -TargetName "npc-overheard.Modelfile"

Write-Host "Creating profile $PlayerProfileName from $BaseModel"
& $ollamaExe create $PlayerProfileName -f $playerModelfile
if ($LASTEXITCODE -ne 0) {
	throw "Failed to create profile $PlayerProfileName"
}

Write-Host "Creating profile $NpcProfileName from $BaseModel"
& $ollamaExe create $NpcProfileName -f $npcModelfile
if ($LASTEXITCODE -ne 0) {
	throw "Failed to create profile $NpcProfileName"
}

Write-Host ""
Write-Host "Created dialogue profiles:"
Write-Host "- $PlayerProfileName"
Write-Host "- $NpcProfileName"
