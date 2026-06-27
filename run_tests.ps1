param(
	[string]$GodotExe = "",
	[string[]]$Only = @(),
	[int]$TestTimeoutSec = 180,
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
		"C:\dev\projects\Godot\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe",
		"C:\dev\projects\Godot\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe",
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

function Invoke-GodotScript {
	param(
		[string]$Executable,
		[string]$ProjectPath,
		[string]$ScriptPath,
		[int]$TimeoutSec,
		[bool]$UseVerbose,
		[bool]$UseHeadless
	)

	$arguments = @()
	if ($UseHeadless) {
		$arguments += "--headless"
	}
	if ($UseVerbose) {
		$arguments += "--verbose"
	}
	$arguments += @("--path", $ProjectPath, "--script", $ScriptPath)

	$processInfo = New-Object System.Diagnostics.ProcessStartInfo
	$processInfo.FileName = $Executable
	$processInfo.Arguments = ($arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " "
	$processInfo.UseShellExecute = $false
	$processInfo.CreateNoWindow = $true
	$processInfo.RedirectStandardOutput = $true
	$processInfo.RedirectStandardError = $true
	$scriptLogKey = ($ScriptPath -replace "^.*[\\/]", "") -replace "\.gd$", ""
	$processInfo.EnvironmentVariables["CITY_SIM_LOG_SUFFIX"] = (
		"test_{0}_{1}" -f $PID, $scriptLogKey
	) -replace "[^A-Za-z0-9_-]", "_"

	$process = New-Object System.Diagnostics.Process
	$process.StartInfo = $processInfo
	$timedOut = $false
	$output = @()
	$exitCode = -1
	try {
		if (-not $process.Start()) {
			throw "Failed to start Godot process."
		}

		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()

		if ($TimeoutSec -gt 0) {
			$completed = $process.WaitForExit($TimeoutSec * 1000)
		}
		else {
			$process.WaitForExit()
			$completed = $true
		}

		if (-not $completed) {
			$timedOut = $true
			Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
			$process.WaitForExit(5000) | Out-Null
		}
		else {
			# Ensure redirected streams are drained and ExitCode is current.
			$process.WaitForExit()
			$process.Refresh()
		}

		$stdout = $stdoutTask.Result
		$stderr = $stderrTask.Result
		if (-not [string]::IsNullOrEmpty($stdout)) {
			$output += $stdout -split "\r?\n"
		}
		if (-not [string]::IsNullOrEmpty($stderr)) {
			$output += $stderr -split "\r?\n"
		}
		if ($timedOut) {
			$output += "TEST_TIMEOUT: Godot script exceeded ${TimeoutSec}s and was killed."
		}
		$exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
	}
	finally {
		if ($null -ne $process) {
			$process.Dispose()
		}
	}
	return [pscustomobject]@{
		Output = @($output)
		ExitCode = $exitCode
		TimedOut = $timedOut
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

function Resolve-TestKeyFilter {
	param([string[]]$RawKeys)

	$keys = New-Object System.Collections.Generic.List[string]
	foreach ($rawKey in $RawKeys) {
		if ([string]::IsNullOrWhiteSpace($rawKey)) {
			continue
		}
		foreach ($part in ($rawKey -split ",")) {
			$trimmed = $part.Trim()
			if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
				$keys.Add($trimmed)
			}
		}
	}
	return @($keys)
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
		Key = "locale"
		Label = "Locale Test"
		Script = "res://tools/codex_locale_test.gd"
	}
	[pscustomobject]@{
		Key = "economy"
		Label = "Economy Test"
		Script = "res://tools/codex_economy_test.gd"
	}
	[pscustomobject]@{
		Key = "inventory"
		Label = "Inventory Adapter"
		Script = "res://tools/codex_inventory_adapter_test.gd"
	}
	[pscustomobject]@{
		Key = "retailgame"
		Label = "Retail Work Sort Minigame"
		Script = "res://tools/codex_retail_work_sort_minigame_test.gd"
	}
	[pscustomobject]@{
		Key = "teachergame"
		Label = "Teacher Lesson Minigame"
		Script = "res://tools/codex_teacher_lesson_minigame_test.gd"
	}
	[pscustomobject]@{
		Key = "cookinggame"
		Label = "Cooking Ingredient Catch Minigame"
		Script = "res://tools/codex_cooking_ingredient_catch_minigame_test.gd"
	}
	[pscustomobject]@{
		Key = "warehousegame"
		Label = "Warehouse Stack Minigame"
		Script = "res://tools/codex_warehouse_stack_minigame_test.gd"
	}
	[pscustomobject]@{
		Key = "serviceflow"
		Label = "Service Flow Minigame"
		Script = "res://tools/codex_service_flow_minigame_test.gd"
	}
	[pscustomobject]@{
		Key = "farmwork"
		Label = "Farm Work Scene"
		Script = "res://tools/codex_farm_work_scene_test.gd"
	}
	[pscustomobject]@{
		Key = "farm_ui_flow"
		Label = "Farm UI Worker/Owner Flow"
		Script = "res://tools/codex_farm_ui_flow_test.gd"
	}
	[pscustomobject]@{
		Key = "farmassets"
		Label = "Quaternius Farm Assets"
		Script = "res://tools/codex_quaternius_farm_asset_probe.gd"
	}
	[pscustomobject]@{
		Key = "farm"
		Label = "Farm Scene/Production"
		Script = "res://tools/codex_farm_scene_probe.gd"
	}
	[pscustomobject]@{
		Key = "grass"
		Label = "Scatter Grass Scene"
		Script = "res://tools/codex_exterior_grass_scene_probe.gd"
	}
	[pscustomobject]@{
		Key = "churchscene"
		Label = "Church Scene"
		Script = "res://tools/codex_church_scene_probe.gd"
	}
	[pscustomobject]@{
		Key = "forest"
		Label = "Biome Scatter Scenes"
		Script = "res://tools/codex_forest_multimesh_scene_probe.gd"
	}
	[pscustomobject]@{
		Key = "farm_live_delivery"
		Label = "Farm Live Delivery"
		Script = "res://tools/codex_farm_live_delivery_test.gd"
	}
	[pscustomobject]@{
		Key = "factory_delivery"
		Label = "Factory Delivery"
		Script = "res://tools/codex_factory_delivery_test.gd"
	}
	[pscustomobject]@{
		Key = "first_day_delivery"
		Label = "First-Day Delivery Seed"
		Script = "res://tools/codex_first_day_delivery_seed_test.gd"
	}
	[pscustomobject]@{
		Key = "vehicle"
		Label = "Vehicle Transport"
		Script = "res://tools/codex_vehicle_transport_test.gd"
	}
	[pscustomobject]@{
		Key = "taxi"
		Label = "Taxi Service"
		Script = "res://tools/codex_taxi_service_test.gd"
	}
	[pscustomobject]@{
		Key = "vehicle_main"
		Label = "Main Scene Vehicle Drive"
		Script = "res://tools/codex_vehicle_main_drive_test.gd"
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
		TimeoutSec = 240
	}
	[pscustomobject]@{
		Key = "gamesmoke"
		Label = "Game Scene Smoke"
		Script = "res://tools/codex_game_smoke_test.gd"
	}
	[pscustomobject]@{
		Key = "fps"
		Label = "FPS Probe"
		Script = "res://tools/codex_fps_probe.gd"
		Optional = $true
		Headless = $true
		TimeoutSec = 180
	}
	[pscustomobject]@{
		Key = "visuallod"
		Label = "Visual LOD Probe"
		Script = "res://tools/codex_visual_lod_probe.gd"
	}
	[pscustomobject]@{
		Key = "fallsafe"
		Label = "Citizen Fall Respawn"
		Script = "res://tools/codex_citizen_fall_respawn_test.gd"
	}
	[pscustomobject]@{
		Key = "multiplayer"
		Label = "Multiplayer Host Connect"
		Script = "res://tools/codex_multiplayer_host_connect_test.gd"
	}
	[pscustomobject]@{
		Key = "save_roundtrip"
		Label = "Savegame Roundtrip"
		Script = "res://tools/codex_savegame_roundtrip_probe.gd"
	}
	[pscustomobject]@{
		Key = "mp2process"
		Label = "Multiplayer Two-Process"
		Script = "res://tools/codex_multiplayer_two_process_test.gd"
		Optional = $true
		TimeoutSec = 300
	}
	[pscustomobject]@{
		Key = "liveeconomy"
		Label = "Live Economy Food Integration"
		Script = "res://tools/codex_live_economy_food_test.gd"
	}
	[pscustomobject]@{
		Key = "entry"
		Label = "Building Entry Travel"
		Script = "res://tools/codex_building_entry_travel_test.gd"
	}
	[pscustomobject]@{
		Key = "entryregression"
		Label = "Building Entry Regression"
		Script = "res://tools/codex_building_entry_regression_test.gd"
		TimeoutSec = 240
	}
	[pscustomobject]@{
		Key = "selection"
		Label = "Selection Hit Test"
		Script = "res://tools/codex_selection_hit_test.gd"
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
		Key = "stuckescape"
		Label = "Citizen Stuck Escape"
		Script = "res://tools/codex_citizen_stuck_escape_test.gd"
	}
	[pscustomobject]@{
		Key = "navsim"
		Label = "Sim Components Smoke"
		Script = "res://tools/codex_sim_components_test.gd"
	}
	[pscustomobject]@{
		Key = "personality"
		Label = "Personality Scoring"
		Script = "res://tools/codex_personality_scoring_test.gd"
	}
	[pscustomobject]@{
		Key = "goalcooldown"
		Label = "Goal Cooldown"
		Script = "res://tools/codex_goal_cooldown_test.gd"
	}
	[pscustomobject]@{
		Key = "servicewindow"
		Label = "Service Arrival Window"
		Script = "res://tools/codex_service_arrival_window_test.gd"
	}
	[pscustomobject]@{
		Key = "workrules"
		Label = "Work Rules"
		Script = "res://tools/codex_work_rules_test.gd"
	}
	[pscustomobject]@{
		Key = "travelsafety"
		Label = "Travel Safety"
		Script = "res://tools/codex_travel_safety_test.gd"
	}
	[pscustomobject]@{
		Key = "socialneed"
		Label = "Social Need"
		Script = "res://tools/codex_social_need_test.gd"
	}
	[pscustomobject]@{
		Key = "socialvisit"
		Label = "Social Visit Goal"
		Script = "res://tools/codex_social_visit_test.gd"
	}
	[pscustomobject]@{
		Key = "emotion"
		Label = "Emotion Model"
		Script = "res://tools/codex_emotion_test.gd"
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
		TimeoutSec = 240
	}
	[pscustomobject]@{
		Key = "navedge"
		Label = "Citizen Edge Step"
		Script = "res://tools/codex_navigation_edge_step_test.gd"
	}
	[pscustomobject]@{
		Key = "navscandiag"
		Label = "Scan Diagnostic"
		Script = "res://tools/codex_scan_diagnose_test.gd"
	}
	[pscustomobject]@{
		Key = "sky"
		Label = "Sky Probe"
		Script = "res://tools/codex_sky_probe.gd"
		Optional = $true
		Headless = $false
	}
)

$onlyKeys = Resolve-TestKeyFilter -RawKeys $Only

$selectedTests = $availableTests | Where-Object {
	if ($onlyKeys.Count -gt 0) {
		return $onlyKeys -contains $_.Key
	}
	if ($_.Key -eq "sky") {
		return $IncludeSky.IsPresent
	}
	if ($_.Optional) {
		return $false
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
	$timeoutSec = $TestTimeoutSec
	if ($TestTimeoutSec -gt 0 -and $null -ne $test.PSObject.Properties["TimeoutSec"]) {
		$timeoutSec = [Math]::Max($TestTimeoutSec, [int]$test.TimeoutSec)
	}
	$useHeadless = $true
	if ($null -ne $test.PSObject.Properties["Headless"]) {
		$useHeadless = [bool]$test.Headless
	}
	$result = Invoke-GodotScript -Executable $godotConsole -ProjectPath $projectPath -ScriptPath $test.Script -TimeoutSec $timeoutSec -UseVerbose:$VerboseGodot.IsPresent -UseHeadless:$useHeadless
	$ok = (-not $result.TimedOut) -and ($result.ExitCode -eq 0) -and (Test-GodotOutputHealthy -OutputLines $result.Output)
	$results.Add([pscustomobject]@{
		Key = $test.Key
		Label = $test.Label
		ExitCode = $result.ExitCode
		TimedOut = $result.TimedOut
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
