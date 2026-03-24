param(
	[string]$GodotExe = "",
	[switch]$VerboseGodot
)

$runner = Join-Path $PSScriptRoot "run_tests.ps1"

if (-not (Test-Path $runner)) {
	throw "run_tests.ps1 not found next to run_tests_quick.ps1"
}

& $runner -GodotExe $GodotExe -Only @("parse", "economy", "occupancy") -VerboseGodot:$VerboseGodot.IsPresent
exit $LASTEXITCODE
