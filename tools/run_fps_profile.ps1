param(
	[string]$GodotExe = "",
	[string]$OutputPath = "",
	[int]$WarmupFrames = 120,
	[int]$MeasureFrames = 360,
	[int]$TimeoutSec = 180,
	[switch]$Headless
)

$ErrorActionPreference = "Stop"

function ConvertTo-ProcessArgument {
	param([string]$Value)

	if ($null -eq $Value -or $Value.Length -eq 0) {
		return '""'
	}
	if ($Value -notmatch '[\s"]') {
		return $Value
	}
	$escaped = $Value -replace '(\\*)"', '$1$1\"'
	$escaped = $escaped -replace '(\\+)$', '$1$1'
	return '"' + $escaped + '"'
}

function Resolve-GodotExecutable {
	param(
		[string]$RequestedPath,
		[bool]$UseHeadless
	)

	if ($RequestedPath -and (Test-Path $RequestedPath)) {
		return (Resolve-Path $RequestedPath).Path
	}
	if ($env:GODOT_EXE -and (Test-Path $env:GODOT_EXE)) {
		return (Resolve-Path $env:GODOT_EXE).Path
	}
	if ($env:GODOT_CONSOLE_EXE -and (Test-Path $env:GODOT_CONSOLE_EXE)) {
		if ($UseHeadless) {
			return (Resolve-Path $env:GODOT_CONSOLE_EXE).Path
		}
		$guiFromEnv = $env:GODOT_CONSOLE_EXE -replace "_console\.exe$", ".exe"
		if (Test-Path $guiFromEnv) {
			return (Resolve-Path $guiFromEnv).Path
		}
		return (Resolve-Path $env:GODOT_CONSOLE_EXE).Path
	}

	$guiCandidates = @(
		"C:\dev\projects\Godot\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64.exe",
		"C:\dev\projects\Godot\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64.exe",
		"C:\dev\projects\Godot\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64.exe"
	)
	$consoleCandidates = @(
		"C:\dev\projects\Godot\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe",
		"C:\dev\projects\Godot\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe",
		"C:\dev\projects\Godot\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64_console.exe"
	)

	$candidates = if ($UseHeadless) { $consoleCandidates + $guiCandidates } else { $guiCandidates + $consoleCandidates }
	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return (Resolve-Path $candidate).Path
		}
	}

	$filter = if ($UseHeadless) { "Godot*_console.exe" } else { "Godot*.exe" }
	$found = Get-ChildItem -Path "C:\dev\projects\Godot" -Filter $filter -Recurse -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -notlike "*Sharp*" } |
		Sort-Object LastWriteTime -Descending |
		Select-Object -First 1
	if ($null -ne $found) {
		return $found.FullName
	}

	throw "Godot executable not found. Pass -GodotExe or set GODOT_EXE/GODOT_CONSOLE_EXE."
}

function Read-CompletedReport {
	param([string]$Path)

	if (-not (Test-Path $Path)) {
		return $null
	}
	try {
		$report = Get-Content -Raw -Path $Path | ConvertFrom-Json -ErrorAction Stop
		if ($report.completed -eq $true) {
			return $report
		}
	}
	catch {
		return $null
	}
	return $null
}

$projectPath = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$profileDir = Join-Path $projectPath "logs\fps_profiles"
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
	$OutputPath = Join-Path $profileDir ("fps_profile_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputPathForGodot = $OutputPath -replace "\\", "/"
$godot = Resolve-GodotExecutable -RequestedPath $GodotExe -UseHeadless:$Headless.IsPresent

$arguments = @()
if ($Headless.IsPresent) {
	$arguments += "--headless"
}
$arguments += @(
	"--path", $projectPath,
	"--script", "res://tools/codex_fps_probe.gd",
	"--",
	"--profile-output=$outputPathForGodot",
	"--warmup=$WarmupFrames",
	"--frames=$MeasureFrames"
)

Write-Host "Godot:   $godot"
Write-Host "Project: $projectPath"
Write-Host "Output:  $OutputPath"
Write-Host "Mode:    $(if ($Headless.IsPresent) { "headless" } else { "renderer" })"
Write-Host ""

$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $godot
$processInfo.Arguments = ($arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " "
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $Headless.IsPresent
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.EnvironmentVariables["CITY_SIM_LOG_SUFFIX"] = ("fps_profile_{0}" -f $PID)

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo
$timedOut = $false
$report = $null

try {
	if (-not $process.Start()) {
		throw "Failed to start Godot process."
	}
	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	$startedAt = Get-Date

	while ($true) {
		$report = Read-CompletedReport -Path $OutputPath
		if ($null -ne $report) {
			break
		}
		if ($process.HasExited) {
			break
		}
		if ($TimeoutSec -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -gt $TimeoutSec) {
			$timedOut = $true
			break
		}
		Start-Sleep -Milliseconds 250
	}

	if (-not $process.HasExited) {
		Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
		$process.WaitForExit(5000) | Out-Null
	}

	$stdout = $stdoutTask.Result
	$stderr = $stderrTask.Result
	if (-not [string]::IsNullOrWhiteSpace($stdout)) {
		Write-Host $stdout.Trim()
	}
	if (-not [string]::IsNullOrWhiteSpace($stderr)) {
		Write-Host $stderr.Trim()
	}
}
finally {
	if ($null -ne $process) {
		$process.Dispose()
	}
}

if ($null -eq $report) {
	$report = Read-CompletedReport -Path $OutputPath
}

if ($null -eq $report) {
	if ($timedOut) {
		Write-Error "FPS profile timed out after ${TimeoutSec}s and no complete report was written."
	}
	else {
		Write-Error "FPS profile failed: no complete report was written."
	}
	exit 1
}

$fps = $report.fps
$render = $report.render
$cpu = $report.cpu
$visualLod = $report.visual_lod

Write-Host ""
Write-Host "FPS profile complete"
Write-Host ("avg_fps={0:N1} avg_ms={1:N2} p95_ms={2:N2} p99_ms={3:N2} max_ms={4:N2}" -f `
	[double]$fps.avg_fps, [double]$fps.avg_ms, [double]$fps.p95_ms, [double]$fps.p99_ms, [double]$fps.max_ms)
Write-Host ("draw_calls_avg={0:N0} primitives_avg={1:N0} render_objects_avg={2:N0}" -f `
	[double]$render.draw_calls_avg, [double]$render.primitives_avg, [double]$render.render_objects_avg)
Write-Host ("process_ms_avg={0:N2} physics_ms_avg={1:N2}" -f `
	[double]$cpu.process_ms_avg, [double]$cpu.physics_ms_avg)
if ($null -ne $visualLod) {
	Write-Host ("visual_lod meshes={0} lights={1} hidden_debug={2}" -f `
		[int]$visualLod.configured_meshes, [int]$visualLod.configured_lights, [int]$visualLod.hidden_debug_meshes)
}
Write-Host "report=$OutputPath"
