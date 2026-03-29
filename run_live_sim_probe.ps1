param(
	[string]$GodotExe = "",
	[switch]$VerboseGodot
)

$ErrorActionPreference = "Stop"
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
	$PSNativeCommandUseErrorActionPreference = $false
}

function Resolve-GodotConsoleExe {
	param([string]$RequestedPath)

	if ($RequestedPath -and (Test-Path $RequestedPath)) {
		return (Resolve-Path $RequestedPath).Path
	}

	if ($env:GODOT_CONSOLE_EXE -and (Test-Path $env:GODOT_CONSOLE_EXE)) {
		return (Resolve-Path $env:GODOT_CONSOLE_EXE).Path
	}

	$candidates = @(
		"C:\dev\projects\Godot\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64_console.exe",
		"C:\dev\projects\Godot\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe"
	)

	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return (Resolve-Path $candidate).Path
		}
	}

	throw "Godot console executable not found. Pass -GodotExe or set GODOT_CONSOLE_EXE."
}

function Invoke-GodotScript {
	param(
		[string]$Executable,
		[string]$ProjectPath,
		[string]$ScriptPath,
		[bool]$UseVerbose
	)

	$args = @("--headless")
	if ($UseVerbose) {
		$args += "--verbose"
	}
	$args += @("--path", $ProjectPath, "--script", $ScriptPath)

	$stdoutPath = [System.IO.Path]::GetTempFileName()
	$stderrPath = [System.IO.Path]::GetTempFileName()
	try {
		$process = Start-Process -FilePath $Executable `
			-ArgumentList $args `
			-NoNewWindow `
			-Wait `
			-PassThru `
			-RedirectStandardOutput $stdoutPath `
			-RedirectStandardError $stderrPath

		$output = @()
		if (Test-Path $stdoutPath) {
			$output += Get-Content -Path $stdoutPath
		}
		if (Test-Path $stderrPath) {
			$output += Get-Content -Path $stderrPath
		}
		return [pscustomobject]@{
			Output = @($output)
			ExitCode = $process.ExitCode
		}
	}
	finally {
		if (Test-Path $stdoutPath) {
			Remove-Item -Path $stdoutPath -Force -ErrorAction SilentlyContinue
		}
		if (Test-Path $stderrPath) {
			Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
		}
	}
}

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotConsole = Resolve-GodotConsoleExe -RequestedPath $GodotExe

Write-Host "Godot:   $godotConsole"
Write-Host "Project: $projectPath"
Write-Host "Script:  res://tools/codex_live_sim_probe.gd"
Write-Host ""

$result = Invoke-GodotScript `
	-Executable $godotConsole `
	-ProjectPath $projectPath `
	-ScriptPath "res://tools/codex_live_sim_probe.gd" `
	-UseVerbose:$VerboseGodot.IsPresent

$result.Output | ForEach-Object { Write-Host $_ }

exit $result.ExitCode
