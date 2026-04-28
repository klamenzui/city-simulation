param(
	[string]$GodotExe = "",
	[switch]$VerboseGodot
)

$runner = Join-Path $PSScriptRoot "run_tests.ps1"

if (-not (Test-Path $runner)) {
	throw "run_tests.ps1 not found next to run_tests_nav.ps1"
}

& $runner -GodotExe $GodotExe -Only @("route", "crosswalk", "navgrid", "navconfig", "navsim", "navroute") -VerboseGodot:$VerboseGodot.IsPresent
exit $LASTEXITCODE
