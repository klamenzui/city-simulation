param(
	[string]$GodotExe = "",
	[string[]]$Only = @(),
	[switch]$IncludeSky,
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

	$found = Get-ChildItem -Path "C:\dev\projects\Godot" -Filter "Godot*_console.exe" -Recurse -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime -Descending |
		Select-Object -First 1

	if ($null -ne $found) {
		return $found.FullName
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
		$exitCode = $process.ExitCode
	}
	finally {
		if (Test-Path $stdoutPath) {
			Remove-Item -Path $stdoutPath -Force -ErrorAction SilentlyContinue
		}
		if (Test-Path $stderrPath) {
			Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
		}
	}
	return [pscustomobject]@{
		Output = @($output)
		ExitCode = $exitCode
	}
}

function Test-GodotOutputHealthy {
	param([string[]]$OutputLines)

	$errorPatterns = @(
		"SCRIPT ERROR:",
		"Parse Error:",
		"Compile Error:",
		"ERROR: Failed to load script",
		"Invalid call. Nonexistent function 'new' in base 'GDScript'."
	)

	foreach ($line in $OutputLines) {
		foreach ($pattern in $errorPatterns) {
			if ($line -like "*$pattern*") {
				return $false
			}
		}
	}

	return $true
}

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotConsole = Resolve-GodotConsoleExe -RequestedPath $GodotExe

$availableTests = @(
	[pscustomobject]@{
		Key = "parse"
		Label = "Parse Check"
		Script = "res://tools/codex_parse_check.gd"
	}
	[pscustomobject]@{
		Key = "economy"
		Label = "Economy Test"
		Script = "res://tools/codex_economy_test.gd"
	}
	[pscustomobject]@{
		Key = "occupancy"
		Label = "Building Occupancy Test"
		Script = "res://tools/codex_building_occupancy_test.gd"
	}
	[pscustomobject]@{
		Key = "runtime"
		Label = "Runtime LOD/Conversation Test"
		Script = "res://tools/codex_runtime_lod_conversation_test.gd"
	}
	[pscustomobject]@{
		Key = "route"
		Label = "Route Probe"
		Script = "res://tools/codex_route_probe.gd"
	}
	[pscustomobject]@{
		Key = "crosswalk"
		Label = "Crosswalk Audit"
		Script = "res://tools/codex_crosswalk_audit.gd"
	}
	[pscustomobject]@{
		Key = "navgrid"
		Label = "Local Grid Topology"
		Script = "res://tools/codex_local_grid_topology_test.gd"
	}
	[pscustomobject]@{
		Key = "navconfig"
		Label = "Citizen Config Drift"
		Script = "res://tools/codex_citizen_config_drift_test.gd"
	}
	[pscustomobject]@{
		Key = "navsim"
		Label = "Sim Components Smoke"
		Script = "res://tools/codex_sim_components_test.gd"
	}
	[pscustomobject]@{
		Key = "navfacade"
		Label = "Facade Caller Drift"
		Script = "res://tools/codex_facade_caller_drift_test.gd"
	}
	[pscustomobject]@{
		Key = "navroute"
		Label = "Citizen Navigation Route"
		Script = "res://tools/codex_navigation_route_test.gd"
	}
	[pscustomobject]@{
		Key = "sky"
		Label = "Sky Probe"
		Script = "res://tools/codex_sky_probe.gd"
		Optional = $true
	}
)

$selectedTests = $availableTests | Where-Object {
	if ($Only.Count -gt 0) {
		return $Only -contains $_.Key
	}
	if ($_.Key -eq "sky") {
		return $IncludeSky.IsPresent
	}
	return $true
}

if ($selectedTests.Count -eq 0) {
	throw "No tests selected. Use -Only parse,economy,occupancy,... or omit -Only."
}

Write-Host "Godot:   $godotConsole"
Write-Host "Project: $projectPath"
Write-Host ""

$results = New-Object System.Collections.Generic.List[object]

foreach ($test in $selectedTests) {
	Write-Host "==> $($test.Label) [$($test.Key)]"
	$result = Invoke-GodotScript -Executable $godotConsole -ProjectPath $projectPath -ScriptPath $test.Script -UseVerbose:$VerboseGodot.IsPresent
	$ok = ($result.ExitCode -eq 0) -and (Test-GodotOutputHealthy -OutputLines $result.Output)
	$results.Add([pscustomobject]@{
		Key = $test.Key
		Label = $test.Label
		ExitCode = $result.ExitCode
		Passed = $ok
		Output = $result.Output
	})

	$result.Output | ForEach-Object { Write-Host $_ }
	Write-Host ""
}

$failed = @($results | Where-Object { -not $_.Passed })

Write-Host "Summary"
Write-Host "-------"
foreach ($result in $results) {
	$status = if ($result.Passed) { "PASS" } else { "FAIL" }
	Write-Host ("{0,-8} {1}" -f $status, $result.Label)
}

if ($failed.Count -gt 0) {
	exit 1
}

exit 0
