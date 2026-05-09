# Citizen Sim Layer — Migration Roadmap

**Status (2026-05-08):** **neuer Citizen-Stack ist produktiv aktiv.**
`CitizenNew.tscn` nutzt `Entities/Citizens/New/Citizen.gd` mit `class_name Citizen`.
Die alte Root-Szene `Entities/Citizens/Citizen.tscn` und der alte Monolith
`Entities/Citizens/Citizen.gd` wurden entfernt.

---

## Architektur-Ziel

```
Entities/Citizens/New/
├── CitizenController.gd      ← Movement (CharacterBody3D, Layer 1-4)
├── Navigation/...            ← Pathfinding, Perception, Steering, Jump, …
├── Debug/...                 ← Logger, DebugDraw
├── Sim/                      ← NEW: Sim-Layer
│   ├── CitizenSimulation.gd  ← Orchestrator (sim_tick, set_world, hält Komponenten)
│   ├── CitizenRestPose.gd    ← ✅ erste Komponente
│   ├── CitizenIdentity.gd    ← ⏳ home/job/wallet/needs/favorites
│   ├── CitizenLocation.gd    ← ⏳ inside_building, enter/leave/exit
│   ├── CitizenScheduler.gd   ← ⏳ decision_cooldown, schedule_offset, work_minutes_today
│   ├── CitizenLodComponent.gd ← ⏳ simulation_lod_tier, commitments
│   └── CitizenDebugFacade.gd ← ⏳ debug_log_once, debug summaries
└── Citizen.gd                ← extends CitizenController + holds CitizenSimulation,
                                 exposes legacy Citizen.gd API to existing callers
```

`Citizen.gd` ist der produktive Adapter zwischen Controller, Sim-Komponenten und
bestehenden Callern (`CitizenAgent`, `CitizenPlanner`, `World`, GOAP Actions,
`CitizenSimulationLodController`, `CitizenFactory`). Die Legacy-API bleibt nur als
Kompatibilitaetsschicht erhalten; der alte Monolith ist nicht mehr Teil des Projekts.

---

## Migrations-Reihenfolge (vorgeschlagen)

Empfehlung: vom Einfachsten zum Komplexesten, sodass jede extracted Komponente
**isoliert getestet** werden kann, bevor die nächste ansteht.

| # | Komponente | LOC (geschätzt) | Komplexität | Caller-Impact |
|---|---|---:|---|---|
| 1 | **RestPose** ✅ | ~40 | trivial | RelaxAtBenchAction, RelaxAtParkAction |
| 2 | **Identity** ✅ | ~50 | leicht | viele (Lese-Zugriffe auf home/job/wallet/needs) |
| 3 | **Location** ✅ | ~80 (+stubs) | mittel | GoToBuildingAction, World, alle Action-Callbacks |
| 3.5 | **BenchReservation** ✅ | ~10 | trivial | RelaxAt*Action + Location-Stub-Replace |
| 4 | **LodComponent** ✅ | ~280 | mittel | CitizenSimulationLodController (zentral). Side-Effects (physics_process, presence, world.notify) bleiben auf `Citizen.gd`; `_nav_agent.avoidance_enabled` aus Legacy entfällt — neuer Stack hat kein NavigationAgent3D. |
| 5 | **Scheduler** ✅ | ~200 | hoch | CitizenAgent, CitizenPlanner. `prepare_go_to_target` und `handle_unreachable_target` sind auf `Citizen.gd` als **vereinfachte Stubs** ohne Building-Discovery-Substitution — die Legacy-`_find_alternative_for_building`-Logik wartet auf einen separaten Building-Discovery-Service. |
| 8 | **ManualControl** ✅ | ~50 | leicht | Player-Control + Click-Move-Mode. `Citizen.gd` orchestriert Side-Effects (rest-pose, building exit, travel stop) bei Mode-Wechsel. Autonomous-Flag direkt auf `Citizen.gd` als `@export`. |
| 6 | **DebugFacade** ✅ | ~50 | leicht | Action-Skripte, GOAP, Planner (`debug_log`, `debug_log_once_per_day`). `get_*_debug_summary` migriert mit Scheduler. |
| 7 | **TraceState** ✅ | ~50 | leicht | RuntimeDebugLogger (`_update_trace_navigation_state`, `get_trace_debug_summary`) |

Nach jeder Migration: `parse`, `navconfig`, `navroute` müssen grün bleiben.

---

## Pattern für eine Komponenten-Extraktion

1. **Identifizieren** der Felder + Methoden in `Entities/Citizens/Citizen.gd`.
2. **Neue Datei** in `Sim/CitizenXxx.gd` mit `class_name CitizenXxx extends RefCounted`.
3. **Konstruktor** mit `_init(p_owner: Node)` — speichert Owner-Referenz.
4. **Verhalten kapseln**: alle relevanten Felder in die Komponente, alle Methoden umziehen.
5. **In `CitizenSimulation`** wiren: Member anlegen, in `_init` instantiieren, in `tick()` aufrufen.
6. **In `Citizen.gd`** API-Methoden hinzufügen, die an die Komponente delegieren.
7. **Test**: parse ✓, ggf. eigener kleiner Komponenten-Test im `tools/`-Ordner.
8. **Wenn der Caller-Set bekannt ist**: Caller-Drift-Test erweitern.

---

## Offene Fragen

- **Identity als Daten oder als Komponente?** Reine Daten (home, job, wallet, needs)
  könnten direkt auf `Citizen.gd` leben (einfacherer Property-Access). Behaviour-Kapselung
  als RefCounted lohnt sich nur, wenn es Logik gibt (Validation, Events, Cache).
- **`balance.json` für Schwellen?** Hunger/Energy-Schwellen leben im alten `Citizen.gd`
  als `@export`-Felder. Im Zuge der Scheduler-Migration entscheiden, ob diese in
  `config/balance.json` wandern.
- **Wann wird der neue Stack produktiv?** **Erreicht am 2026-05-08/09:**
  `CitizenNew.tscn` nutzt `Entities/Citizens/New/Citizen.gd`, Factory/Main zeigen
  auf die neue Szene, der alte Root-Monolith ist entfernt.

## Stubs in `Citizen.gd` (TODO bei späteren Migrationen)

- ~~`release_reserved_benches(world, building)`~~ ✅ extrahiert als `CitizenBenchReservation`.
- ~~`_update_trace_navigation_state(...)`~~ ✅ extrahiert als `CitizenTraceState`. Die alten Sensor-Hit-Felder (`_trace_last_forward_hit` etc.) wurden bewusst NICHT mitgenommen — der neue Stack hat keine entsprechenden RayCasts.
- `_set_position_grounded()` ist im neuen Stack vereinfacht zu `global_position = pos; velocity = ZERO`. Wenn das Locomotion-Helper-Verhalten zurück muss, gehört es als Movement-Layer-Helper auf den `CitizenController`.

**Status nach 8/8 (2026-04-27):**

- `release_reserved_benches` ✅ extrahiert.
- `_update_trace_navigation_state` ✅ extrahiert.
- `_set_position_grounded` weiterhin als simple Variante (`global_position = pos; velocity = ZERO`) — voller Locomotion-Snap kommt mit dem Movement-Helper.
- `prepare_go_to_target` / `handle_unreachable_target` als **vereinfachte Stubs** auf `Citizen.gd`: prüfen den Unreachable-Cache, aber substituieren keine Alternative. Building-Discovery-Service ist eigener Refactor.
- Legacy-Helpers `get_job_debug_summary` / `get_unemployment_debug_reason` / `get_zero_pay_debug_reason` sind auf `Citizen.gd` als Kompatibilitaetsschicht vorhanden. Langfristig gehoeren sie eher zu einem `CitizenStatusReporter`-Service als zur Sim-Schicht.

---

## Test-Anker

| Test-Key | Aufgabe | Sollte FAILen wenn… |
|---|---|---|
| `parse` | Syntax + Main.tscn-Bootstrap | Skript-Parser-Fehler oder Class-Registry-Bruch |
| `navconfig` | Drift Controller@exports ↔ Config | neues @export ohne FIELD_NAMES-Eintrag |
| `navgrid` | LocalGrid-Topologie | jemand `_GRID_NEIGHBORS` reduziert |
| `navsim` | Sim-Komponenten-Smoke (Identity, RestPose) | Komponenten-Defaults driften |
| `navroute` | End-zu-End-Reise (real Map) | Avoidance/Movement bricht; Indikator-Waypoints werden gerissen |

Migrations-Schutz künftig: ein `navfacade`-Test, der prüft, dass `Citizen.gd` alle
erwarteten Methoden implementiert (Source-Parsing der `has_method`-Aufrufe in
`CitizenAgent.gd` etc.). Sinnvoll, sobald 3+ Komponenten migriert sind.
