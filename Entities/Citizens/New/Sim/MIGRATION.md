# Citizen Sim Layer — Migration Roadmap

**Status (2026-04-27):** **8/8 Komponenten extrahiert** (`CitizenRestPose`, `CitizenIdentity`, `CitizenLocation`, `CitizenBenchReservation`, `CitizenTraceState`, `CitizenDebugFacade`, `CitizenLodComponent`, `CitizenScheduler`).
Old `Citizen.gd` (3.350 Zeilen) lebt unverändert weiter — die Migration ist inhaltlich durch, aber das Aktiv-Schalten der Facade in `Main.tscn` ist eine separate Umstellung mit eigenem Test-Aufwand.

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
└── CitizenFacade.gd          ← extends CitizenController + holds CitizenSimulation,
                                 exposes legacy Citizen.gd API to existing callers
```

`CitizenFacade` ist heute nicht produktiv im Einsatz — sie ist das Migrations-Skelett.
Sobald alle Komponenten migriert sind und alle Caller (`CitizenAgent`, `CitizenPlanner`,
`World`, GOAP Actions, `CitizenSimulationLodController`, `CitizenFactory`) gegen die
Facade getestet wurden, wird:

1. Die Legacy-Datei `Entities/Citizens/Citizen.gd` archiviert
   (Kopie nach `Entities/Citizens/_Archive/` oder im Vault unter `50_Archive/`).
2. `CitizenFacade.gd` umbenannt zu `Citizen.gd` (mit `class_name Citizen`).
3. `Entities/Citizens/CitizenNew.tscn` umbenannt/repointed.

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
| 4 | **LodComponent** ✅ | ~280 | mittel | CitizenSimulationLodController (zentral). Side-Effects (physics_process, presence, world.notify) bleiben auf der Facade; `_nav_agent.avoidance_enabled` aus Legacy entfällt — neuer Stack hat kein NavigationAgent3D. |
| 5 | **Scheduler** ✅ | ~200 | hoch | CitizenAgent, CitizenPlanner. `prepare_go_to_target` und `handle_unreachable_target` sind auf der Facade als **vereinfachte Stubs** ohne Building-Discovery-Substitution — die Legacy-`_find_alternative_for_building`-Logik wartet auf einen separaten Building-Discovery-Service. |
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
6. **In `CitizenFacade`** API-Methoden hinzufügen, die an die Komponente delegieren.
7. **Test**: parse ✓, ggf. eigener kleiner Komponenten-Test im `tools/`-Ordner.
8. **Wenn der Caller-Set bekannt ist**: Caller-Drift-Test erweitern.

---

## Offene Fragen

- **Identity als Daten oder als Komponente?** Reine Daten (home, job, wallet, needs)
  könnten direkt auf der Facade leben (einfacherer Property-Access). Behaviour-Kapselung
  als RefCounted lohnt sich nur, wenn es Logik gibt (Validation, Events, Cache).
- **`balance.json` für Schwellen?** Hunger/Energy-Schwellen leben im alten `Citizen.gd`
  als `@export`-Felder. Im Zuge der Scheduler-Migration entscheiden, ob diese in
  `config/balance.json` wandern.
- **Wann wird die Facade auf `CitizenNew.tscn` aktiv geschaltet?** Variante A: erst
  nach kompletter Migration (Big-Bang). Variante B: sobald genug API-Methoden da sind,
  einen zweiten Test-Citizen mit der Facade aufnehmen und parallel beobachten.
  **Erreicht: Identity + Location sind durch — Variante B ab jetzt möglich.**

## Stubs in der Facade (TODO bei späteren Migrationen)

- ~~`release_reserved_benches(world, building)`~~ ✅ extrahiert als `CitizenBenchReservation`.
- ~~`_update_trace_navigation_state(...)`~~ ✅ extrahiert als `CitizenTraceState`. Die alten Sensor-Hit-Felder (`_trace_last_forward_hit` etc.) wurden bewusst NICHT mitgenommen — der neue Stack hat keine entsprechenden RayCasts.
- `_set_position_grounded()` ist im neuen Stack vereinfacht zu `global_position = pos; velocity = ZERO`. Wenn das Locomotion-Helper-Verhalten zurück muss, gehört es als Movement-Layer-Helper auf den `CitizenController`.

**Status nach 8/8 (2026-04-27):**

- `release_reserved_benches` ✅ extrahiert.
- `_update_trace_navigation_state` ✅ extrahiert.
- `_set_position_grounded` weiterhin als simple Variante (`global_position = pos; velocity = ZERO`) — voller Locomotion-Snap kommt mit dem Movement-Helper.
- `prepare_go_to_target` / `handle_unreachable_target` als **vereinfachte Stubs** auf der Facade: prüfen den Unreachable-Cache, aber substituieren keine Alternative. Building-Discovery-Service ist eigener Refactor.
- Legacy-Helpers `get_job_debug_summary` / `get_unemployment_debug_reason` / `get_zero_pay_debug_reason` sind NICHT auf der Facade — sie hängen von Job-internen Feldern + Wallet-State ab und gehören eher zu einem `CitizenStatusReporter`-Service als zur Sim-Schicht.

---

## Test-Anker

| Test-Key | Aufgabe | Sollte FAILen wenn… |
|---|---|---|
| `parse` | Syntax + Main.tscn-Bootstrap | Skript-Parser-Fehler oder Class-Registry-Bruch |
| `navconfig` | Drift Controller@exports ↔ Config | neues @export ohne FIELD_NAMES-Eintrag |
| `navgrid` | LocalGrid-Topologie | jemand `_GRID_NEIGHBORS` reduziert |
| `navsim` | Sim-Komponenten-Smoke (Identity, RestPose) | Komponenten-Defaults driften |
| `navroute` | End-zu-End-Reise (real Map) | Avoidance/Movement bricht; Indikator-Waypoints werden gerissen |

Migrations-Schutz künftig: ein `navfacade`-Test, der prüft, dass `CitizenFacade` alle
erwarteten Methoden implementiert (Source-Parsing der `has_method`-Aufrufe in
`CitizenAgent.gd` etc.). Sinnvoll, sobald 3+ Komponenten migriert sind.
