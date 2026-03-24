# City Simulation

Godot-4.6-Projekt fuer eine kleine Stadt-Simulation mit Citizens, Gebaeuden, Zeit-/Wirtschaftssystem, Routing, Zebra-Querungen und einer Tag-/Nacht-Visualisierung.

## Projektueberblick

Die Hauptszene ist `Main.tscn`. Beim Start wird die Stadt aufgebaut, das Welt-/Zeit-/Economy-System initialisiert, fehlende Kerngebaeude werden bei Bedarf ergaenzt, Citizens gespawnt und Debug/HUD aufgebaut.

Wichtige Bereiche:

- `Main.tscn` / `main.gd`: Bootstrapping, HUD, Debug, Citizen-Spawn, Auswahl, Logs
- `Simulation/World.gd`: Simulationszeit, Tick-Loop, Economy-/Payday-Anbindung
- `Simulation/Navigation/*`: Road- und Pedestrian-Graph, Crosswalk-Logik
- `Entities/Citizens/*`: Citizen-Logik, Bewegung, Haus/Job/Beduerfnisse
- `Entities/Buildings/*`: Gebaeude, Eingangs-/Access-/Spawn-Punkte, Jobs, Wohnen
- `environment/sky/*`: Tag/Nacht, Sky, Lichtstimmung
- `tools/*`: Headless-Probes und Audits

## Aktueller Funktionsumfang

- Citizens koennen wohnen, arbeiten, essen, Freizeitorte besuchen und Gebaeude betreten/verlassen.
- Das Projekt nutzt lokale Hindernisvermeidung mit Raycasts plus globale Wegfindung ueber den Fussgaenger-Graph.
- Strassenquerungen werden ueber Crosswalk-/Zebra-Knoten modelliert.
- Es gibt ein Zeitmodell mit Pause, Geschwindigkeitsstufen und Tagesfortschritt.
- Economy-System mit Markt, Jobs, Gehalt, Steuern und Welfare ist vorhanden.
- Sky/Ocean und Tag-Nacht-Visualisierung sind an die Simulationszeit gekoppelt.
- Gebaeude- und Strassenmaterialien werden beim Start matter gemacht, damit sie weniger metallisch wirken.

## Projekt starten

Voraussetzung: Godot 4.6.x.

Projektname laut [project.godot](./project.godot): `City Simulation`

Standard-Start:

1. Projekt in Godot oeffnen
2. `Main.tscn` starten

Oder direkt ueber den Editor, da `res://Main.tscn` als `run/main_scene` gesetzt ist.

## Steuerung

Kamera:

- `WASD` oder Pfeiltasten: bewegen
- `Shift`: schneller bewegen
- Maus an Bildschirmrand: Edge-Scroll
- Mausrad: zoomen
- Mittlere Maustaste + ziehen: Kamera drehen
- `Q` / `E`: Kamera drehen

Ingame:

- Linksklick auf Citizen: Auswahl + Citizen-Debug
- Linksklick auf Gebaeude: Auswahl + Gebaeude-Debug
- Linksklick ins Leere: Auswahl aufheben
- `Enter`: Pause/Resume
- UI-Buttons unten links: `Pause`, `0.1x`, `0.5x`, `1.0x`, `2.0x`

## Debug und Logs

Es gibt zwei wichtige Debug-Kanaele:

- Visuell in der Szene: Pfadlinien, Gebaeude-Navigation, Entrance/Access/Spawn-Marker fuer ausgewaehlte Entities
- Datei-Logs: `logs.log` im Projekt-Root

Die Logdatei enthaelt unter anderem:

- `CitizenTrace`: gewaehlter Citizen
- `CitizenTraceAll`: globale Kurztraces
- `MapDump`: Snapshot von Gebaeuden, Citizens, Strassen, Crosswalks und Lichtern

Die Session wird mit `sid=... pid=...` markiert, damit mehrere Laeufe unterscheidbar bleiben.

## Tests

Fuer Headless-Checks gibt es drei kleine PowerShell-Wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests_quick.ps1
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests_nav.ps1
powershell -ExecutionPolicy Bypass -File C:\dev\projects\Godot\city-simulation\run_tests_full.ps1
```

Kurzbeschreibung:

- `run_tests_quick.ps1`: Parse + Economy + Occupancy
- `run_tests_nav.ps1`: Route + Crosswalk
- `run_tests_full.ps1`: Parse + Economy + Occupancy + Route + Crosswalk + Sky

Ausfuehrliche Beschreibung, Parameter und direkte Nutzung von `run_tests.ps1` stehen in [TESTING.md](./TESTING.md).

## Wichtige Tool-Skripte

- `tools/codex_parse_check.gd`: prueft zentrale Ressourcen/Script-Loads
- `tools/codex_economy_test.gd`: Economy-Regressionen
- `tools/codex_building_occupancy_test.gd`: Besucher-/Worker-Zaehlung in Gebaeuden
- `tools/codex_route_probe.gd`: Beispielrouten, Crosswalk-Probes, Spawn-/Entrance-Debug
- `tools/codex_crosswalk_audit.gd`: Audit fuer illegale Strassenquerungen im Graph
- `tools/codex_sky_probe.gd`: Sky/Ocean/Tag-Nacht-Pruefung

## Wichtige Runtime-Dateien

- `logs.log`: aktuelle Simulationslogs
- `TESTING.md`: Testdokumentation
- Analyse-Dokument im Projekt-Root: bisherige Problem-/Fix-Notizen

## Hinweise

- Wenn PowerShell Skripte blockiert, immer mit `-ExecutionPolicy Bypass` starten.
- Der Runner sucht die Godot Console EXE automatisch; alternativ kann `GODOT_CONSOLE_EXE` gesetzt werden.
- Bei Log-Analysen moeglichst nur eine Godot-Instanz gleichzeitig offen haben, damit sich Sessions nicht mischen.
