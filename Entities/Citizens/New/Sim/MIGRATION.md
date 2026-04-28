# Citizen Sim Layer — Migration Roadmap

**Status (2026-04-27):** Skelett gelegt, eine erste Komponente (`CitizenRestPose`) extrahiert.
Old `Citizen.gd` (3.350 Zeilen) lebt unverändert weiter — die Migration läuft inkrementell.

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
| 2 | **Identity** | ~80 | leicht | viele (Lese-Zugriffe auf home/job/wallet/needs) |
| 3 | **Location** | ~150 | mittel | GoToBuildingAction, World, alle Action-Callbacks |
| 4 | **LodComponent** | ~250 | mittel | CitizenSimulationLodController (zentral) |
| 5 | **Scheduler** | ~300 | hoch | CitizenAgent, CitizenPlanner |
| 6 | **DebugFacade** | ~80 | leicht | Action-Skripte (`debug_log_once_per_day`) |
| 7 | **TraceState** | ~60 | leicht | RuntimeDebugLogger (`_update_trace_navigation_state`) |

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
  Empfehlung: B, sobald Identity + Location migriert sind.

---

## Test-Anker

| Test-Key | Aufgabe | Sollte FAILen wenn… |
|---|---|---|
| `parse` | Syntax | Skript-Parser-Fehler |
| `navconfig` | Drift Controller@exports ↔ Config | neues @export ohne FIELD_NAMES-Eintrag |
| `navgrid` | LocalGrid-Topologie | jemand `_GRID_NEIGHBORS` reduziert |
| `navroute` | End-zu-End-Reise | Avoidance/Movement bricht; Indikator-Waypoints werden gerissen |

Migrations-Schutz künftig: ein `navfacade`-Test, der prüft, dass `CitizenFacade` alle
erwarteten Methoden implementiert (Source-Parsing der `has_method`-Aufrufe in
`CitizenAgent.gd` etc.). Sinnvoll, sobald 3+ Komponenten migriert sind.
