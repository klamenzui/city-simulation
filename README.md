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
- Economy-System mit Markt, Jobs, Gehalt, Steuern, Welfare, Gebaeudezustand und oeffentlicher Finanzierung ist vorhanden.
- Sky/Ocean und Tag-Nacht-Visualisierung sind an die Simulationszeit gekoppelt.
- Gebaeude- und Strassenmaterialien werden beim Start matter gemacht, damit sie weniger metallisch wirken.

## Economy-Modell

Die Geldfluesse sind jetzt in drei Ebenen organisiert:

- `CityHall`, `University`, `Park` gelten als oeffentliche Gebaeude.
- `Cafe`, `Cinema`, `Factory`, `Farm`, `ResidentialBuilding`, `Restaurant`, `Shop`, `Supermarket` gelten als wirtschaftliche Gebaeude.
- `EconomySystem` fuehrt die eigentlichen Transfers durch, `Building` speichert Zustand/Konto/Status und `World` orchestriert die taegliche Abrechnung.

Wichtige Regeln:

- `University` und `Park` zahlen keine normale Gewerbesteuer.
- `University` nimmt keine Tuition mehr ein; sie wird komplett ueber `CityHall` finanziert.
- `Park` wird ebenfalls ueber `CityHall` finanziert.
- `CityHall` kann bei Liquiditaetsmangel begrenzt Geld aus `city_reserve` ziehen, statt sofort oeffentliche Dienste sterben zu lassen.
- Wartung/Reparatur zahlen nicht mehr unsichtbar ins Nichts, sondern an konkrete Rollen wie `Janitor`, `MaintenanceWorker`, `Technician` oder `Gardener`.
- Produktionskosten von `Farm` und `Factory` fliessen in den Markt-Account statt einfach zu verschwinden.
- Oeffentliche Gebaeude laufen bei Unterfinanzierung erst in einen weichen `underfunded`-Zustand und schliessen erst nach mehreren schlechten Tagen.
- Wirtschaftliche Gebaeude laufen bei einzelnen Zahlungsproblemen erst in `struggling` und schliessen erst nach wiederholten Ausfaellen.
- Wenn ein Gebaeude wirklich schliesst, verlieren Worker ihren Arbeitsplatz und suchen spaeter neue Jobs.

## Gebaeudefinanzen

Wirtschaftliche Gebaeude rechnen pro Tag grob ueber diese Komponenten:

- Einnahmen
- Lohnkosten
- Steuern
- Wartungskosten
- Produktionskosten
- Gewinn/Verlust

Die Kerngleichung ist:

```text
profit = income - wages - taxes - maintenance - production_costs
```

Zusatzlogik:

- Jedes Gebaeude hat `condition`, `daily_decay`, `maintenance_cost_per_day` und `repair_threshold`.
- Ohne passendes Wartungspersonal sinkt `condition` schneller.
- Schlechter Zustand reduziert Effizienz und Attraktivitaet.
- Wirtschaftliche Gebaeude starten optional mit `economy.buildings.start_balance`, damit sie nicht schon an Tag 2 nur wegen Liquiditaetsarmut kippen.
- Bei unbezahlten Loehnen, Steuern, Wartung oder negativem Gebaeudekonto wechseln wirtschaftliche Gebaeude zuerst in `struggling`.
- Erst nach mehreren verfehlten Zahlungstagen (`max_missed_payment_days_before_closure`) werden sie hart geschlossen.

## Oeffentliche Finanzierung

`CityHall` hat ein eigenes Budget und finanziert damit:

- `University`-Betrieb
- `Park`-Betrieb
- Welfare
- Infrastrukturkosten

Die Finanzierung ist priorisiert:

- minimale Welfare-Basis vor allem anderen
- `University` vor `Park`
- Infrastruktur zuletzt
- bei Budgetmangel werden Teilfinanzierungen und Shortfalls geloggt, statt sofort alles-oder-nichts zu behandeln

Bei der Uni umfasst die Finanzierungsanfrage aktuell:

- `base_operating_cost` als fixer Grundbetrieb
- offene Lohnkosten des Tages
- Wartungskosten, wenn Wartungspersonal vorhanden ist
- Ausgleich eines negativen Kontostands

Wichtig dabei:

- `base_operating_cost` ist nur der feste Sockel
- die eigentliche Tageslast wird dynamisch berechnet als Grundbetrieb + Payroll + Wartung
- im Gebaeude-Debug steht das als `Estimated daily obligations`

Wichtige Reserve-/Soft-Failure-Felder:

- `economy.city_hall.min_operating_balance`
- `economy.city_hall.reserve_transfer_target_balance`
- `economy.city_hall.reserve_transfer_daily_limit`
- `economy.city_hall.max_underfunded_days_before_closure`
- `economy.city_hall.underfunded_efficiency_multiplier`
- `economy.city_hall.underfunded_service_multiplier`

## Jobs und Personal

Neue einfache Jobtypen im Projekt:

- `Professor`
- `Janitor`
- `Gardener`
- `MaintenanceWorker`
- `Technician`

Jeder Job hat jetzt ueber `balance.json` steuerbare:

- `wage_per_hour`
- `required_education`
- `allowed_building_types`

Hinweis zur Uni:

- `Teacher` braucht in diesem Projekt absichtlich keine Vorbildung, damit kein unendlicher Ausbildungs-Kreis entsteht.
- Die Uni braucht fuer den Lehrbetrieb mindestens passendes Lehrpersonal (`Teacher` oder `Professor`).

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
- UI-Buttons unten links: `Pause`, `0.1x`, `0.5x`, `1.0x`, `2.0x`, `Buildings`
- `Buildings`: oeffnet eine sortierte Liste aller Gebaeude, aktive zuerst; aktive Eintraege sind fett markiert

## Debug und Logs

Es gibt zwei wichtige Debug-Kanaele:

- Visuell in der Szene: Pfadlinien, Gebaeude-Navigation, Entrance/Access/Spawn-Marker fuer ausgewaehlte Entities
- Datei-Logs: `logs.log` im Projekt-Root

Die Logdatei enthaelt unter anderem:

- `CitizenTrace`: gewaehlter Citizen
- `CitizenTraceAll`: globale Kurztraces
- `MapDump`: Snapshot von Gebaeuden, Citizens, Strassen, Crosswalks und Lichtern

Die Session wird mit `sid=... pid=...` markiert, damit mehrere Laeufe unterscheidbar bleiben.

## Balancing

Die meisten Gameplay-/Balance-Werte liegen jetzt zentral in `config/balance.json`.
Das ist die Hauptdatei fuer Feintuning von:

- Simulationstempo (`simulation`, `world`, `schedule`)
- Economy und Jobs (`economy`)
- Oeffentliche Finanzierung, Steuern und Welfare (`economy.city_hall`)
- Citizen-Startwerte, Needs und Schwellen (`citizen`)
- Action-Dauern und Action-Effekte (`actions`)
- Planner-/GOAP-Schwellen, Prioritaeten und Reisekosten (`planner`, `goap`)
- Gebaeudeparameter wie Oeffnungszeiten, Capacity, Job-Capacity, Preise, Produktion, Zustand und Wartung (`buildings`, `building`)

Wichtige Beispiele:

- `world.minutes_per_tick`, `world.tick_interval_sec`, `world.speed_multiplier`
- `economy.city_hall.business_tax_rate`, `economy.city_hall.citizen_tax_rate`, `economy.city_hall.unemployment_support`
- `economy.city_hall.min_operating_balance`, `economy.city_hall.reserve_transfer_target_balance`, `economy.city_hall.reserve_transfer_daily_limit`
- `economy.city_hall.max_underfunded_days_before_closure`, `economy.city_hall.underfunded_efficiency_multiplier`, `economy.city_hall.underfunded_service_multiplier`
- `economy.buildings.start_balance`, `economy.buildings.max_missed_payment_days_before_closure`
- `economy.buildings.struggling_efficiency_multiplier`, `economy.buildings.struggling_customer_multiplier`
- `economy.jobs.wage_per_hour_by_title.*`
- `economy.jobs.required_education.*`
- `economy.jobs.allowed_building_types.*`
- `citizen.needs.*`
- `actions.work.*`, `actions.sleep.*`, `actions.eat_restaurant.*`
- `planner.*` fuer Prioritaeten und kritische Schwellen
- `goap.*` fuer Entscheidungsgrenzen, Action-Kosten und Ziel-Reisezeiten
- `buildings.university.*`, `buildings.restaurant.*`, `buildings.park.*`
- `buildings.university.base_operating_cost`, `buildings.park.base_operating_cost`
- `building.condition_start`, `building.daily_decay`, `building.maintenance_cost_per_day`, `building.repair_threshold`

Hinweise:

- Die JSON wird beim Projektstart geladen. Nach Aenderungen am Balancing am besten die Szene bzw. das Spiel neu starten.
- Falls `config/balance.json` unvollstaendig ist, fallen fehlende Werte automatisch auf Default-Werte aus `Simulation/Config/BalanceConfig.gd` zurueck.
- Wenn du neue Balance-Felder einfuehrst, sollten sie sowohl in `config/balance.json` als auch in `Simulation/Config/BalanceConfig.gd` gepflegt werden.

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
