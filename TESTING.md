# Testing

Dieses Projekt hat drei kleine PowerShell-Runner fuer die wichtigsten Headless-Godot-Checks.

## Voraussetzungen

- Godot Console EXE ist installiert.
- Falls PowerShell Skripte blockiert, nutze `-ExecutionPolicy Bypass`.

Standardpfade, die der Runner automatisch probiert:

- `C:\dev\projects\Godot\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64_console.exe`
- `C:\dev\projects\Godot\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe`

Optional kannst du Godot explizit setzen:

```powershell
$env:GODOT_CONSOLE_EXE = "C:\path\to\Godot_v4.6.1-stable_win64_console.exe"
```

## Schnelltest

Prueft nur Syntax/Load + Economy.

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests_quick.ps1
```

Enthaelt:

- Parse Check
- Economy Test
- Building Occupancy Test

## Navigationstest

Prueft nur Routing/Zebra-Themen.

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests_nav.ps1
```

Enthaelt:

- Route Probe
- Crosswalk Audit

## Volltest

Prueft alles Wichtige inklusive Sky/Ocean.

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests_full.ps1
```

Enthaelt:

- Parse Check
- Economy Test
- Building Occupancy Test
- Route Probe
- Crosswalk Audit
- Sky Probe

## Direkter Runner

Alle Wrapper rufen intern `run_tests.ps1` auf. Den kannst du auch direkt mit Parametern benutzen.

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1
```

Beispiele:

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -Only parse,economy
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -Only farm_live_delivery
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -Only first_day_delivery
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -Only workrules
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -Only route,crosswalk
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -Only mp2process
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -IncludeSky
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -VerboseGodot
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests.ps1 -Only liveeconomy -TestTimeoutSec 300
```

Optionale Parameter:

- `-GodotExe "C:\path\to\Godot_v4.6.1-stable_win64_console.exe"`
- `-Only parse,economy,route,crosswalk,sky`
- `-Only parse,economy,occupancy,route,crosswalk,sky`
- `-TestTimeoutSec 180` setzt den Standard-Timeout pro Godot-Test; `0` deaktiviert den Timeout
- `-Only mp2process` fuer den optionalen echten Host/Client-Zwei-Prozess-Test
- `-IncludeSky`
- `-VerboseGodot`

`run_tests.ps1` beendet haengende Godot-Prozesse nach dem Timeout und markiert den Test als `FAIL`.
Einige laengere Tests haben einen eigenen hoeheren Timeout im Runner.
Headless-Tests schreiben ihre Session-Logs in `logs_test_*.log` und `ai_test_*.log`, damit eine laufende Editor-Session nicht ueberschrieben wird.

## Erwartete Ausgabe

Am Ende kommt immer eine kleine Summary:

```text
Summary
-------
PASS     Parse Check
PASS     Economy Test
```

Wenn ein Check fehlschlaegt, beendet sich der Runner mit Exit-Code `1`.

## Dateien

- `run_tests.ps1`: gemeinsamer Haupt-Runner
- `run_tests_quick.ps1`: schneller Alltagscheck
- `run_tests_nav.ps1`: Navigation/Routing
- `run_tests_full.ps1`: groesserer Komplettcheck
- `tools/codex_parse_check.gd`: Ressourcen/Script-Load
- `tools/codex_economy_test.gd`: Economy-Regressionen
- `tools/codex_farm_live_delivery_test.gd`: Main.tscn Farm-Fahrer-Lieferung per Truck zum Supermarkt
- `tools/codex_first_day_delivery_seed_test.gd`: Startwelt hat Farm-Lagerbestand, Fahrer, Supermarkt-Bedarf und erreichbare LKW-Route
- `tools/codex_work_rules_test.gd`: gemeinsame Arbeitsplanungsregeln inklusive krankheitsbedingtem Work-Skip
- `tools/codex_building_occupancy_test.gd`: Besucher-/Worker-Zaehlung in Gebaeuden
- `tools/codex_multiplayer_two_process_test.gd`: echter Host/Client-Zwei-Prozess-Smoke
- `tools/codex_route_probe.gd`: Pfad-/Crosswalk-Probes
- `tools/codex_crosswalk_audit.gd`: Graph-Audit fuer Strassenquerungen
- `tools/codex_sky_probe.gd`: Sky/Ocean/Tag-Nacht
