param(
	[string]$GodotExe = "",
	[string]$Scenario = "res://tools/dialogue_probe_default.json",
	[string[]]$Turns = @(),
	[double]$RuntimeWait = 20.0,
	[double]$ReplyWait = 25.0,
	[int]$AiTail = 80,
	[switch]$Template,
	[switch]$AllowFallback,
	[switch]$VerboseGodot
)

$ErrorActionPreference = "Stop"

function Resolve-GodotConsoleExe {
	param([string]$RequestedPath)

	if ($RequestedPath) {
		return $RequestedPath
	}

	if ($env:GODOT_CONSOLE_EXE) {
		return $env:GODOT_CONSOLE_EXE
	}

	$candidates = @(
		"C:\dev\projects\Godot\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64_console.exe",
		"C:\dev\projects\Godot\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe"
	)

	return $candidates[0]
}

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotConsole = Resolve-GodotConsoleExe -RequestedPath $GodotExe

$args = @("--headless")
if ($VerboseGodot) {
	$args += "--verbose"
}
$args += @(
	"--path", $projectPath,
	"--script", "res://tools/codex_dialogue_probe.gd",
	"--scenario", $Scenario,
	"--runtime-wait", ([string]$RuntimeWait),
	"--reply-wait", ([string]$ReplyWait)
)

if ($Template) {
	$args += "--template"
}
if ($AllowFallback) {
	$args += "--allow-fallback"
}
foreach ($turn in $Turns) {
	$args += @("--turn", $turn)
}

$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $godotConsole
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $true
$quotedArgs = $args | ForEach-Object {
	if ($_ -match '\s') {
		'"{0}"' -f ($_ -replace '"', '\"')
	}
	else {
		$_
	}
}
$processInfo.Arguments = [string]::Join(' ', $quotedArgs)

$process = [System.Diagnostics.Process]::Start($processInfo)
if ($null -eq $process) {
	throw "Failed to start Godot console executable: $godotConsole"
}

$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
$exitCode = $process.ExitCode

if ($stdout) {
	$stdout -split "`r?`n" | Where-Object { $_ -ne "" } | ForEach-Object { Write-Host $_ }
}
if ($stderr) {
	$stderr -split "`r?`n" | Where-Object { $_ -ne "" } | ForEach-Object { Write-Host $_ }
}

$aiLogPath = Join-Path $projectPath "ai.log"
if (Test-Path $aiLogPath) {
	Write-Host ""
	Write-Host "AI log tail ($AiTail lines)"
	Write-Host "-----------------------"
	Get-Content -Path $aiLogPath -Tail $AiTail
}

exit $exitCode
