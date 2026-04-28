# LocalGridPlanner — Detaillierte Erklärung

`LocalGridPlanner.gd` ist **Layer 3** der 4-Schicht-Navigations-Pipeline. Er
baut **um den Citizen herum** ein kleines dual-subdiv. 8-connect-A*-Gitter
(historisch „Hex" genannt, ist aber keines — siehe §3), sondiert jede Zelle
per Physik + Oberflächen-Ray, und sucht den besten Umweg, der so nah wie
möglich am globalen Pfad bleibt.

> **Wichtig:** Der `LocalGridPlanner` selbst macht **keine** Höhen-Scans.
> Er ruft nur `LocalPerception.get_probe_block_info()` und `probe_surface()`
> auf — dort passieren die echten Physik-Abfragen. Siehe Abschnitt
> [Höhen-Sondierung](#höhen-sondierung-deine-idee) für deinen Vorschlag.

---

## 1. Einordnung im Pipeline

| Layer | Datei | Rolle |
|------|------|------|
| 1. Global Path | (Pedestrian-Graph) | Lange Route von A nach B |
| 2. Local Perception | `LocalPerception.gd` | „Was ist vor / unter mir?" — einzelne Probes |
| **3. Local Grid** | **`LocalGridPlanner.gd`** | **Umweg-Gitter um Hindernisse** |
| 4. Steering / Move | (Controller / Movement) | Body bewegen, sliden, springen |

Layer 3 wird nur aktiviert, wenn Layer 2 sagt „Pfad voraus blockiert" oder
der Citizen auf einer falschen Oberfläche (z. B. Straße) steht.

---

## 2. Eingang & Ausgang von `build_detour()`

```
build_detour(
	desired_direction: Vector3,    # Richtung zum nächsten globalen Wegpunkt
	global_path: PackedVector3Array,
	path_index: int,                # aktueller Wegpunkt-Index
	target_position: Vector3        # Endziel
) -> Dictionary
```

Rückgabe-Dictionary (Schlüssel siehe `RESULT_KEY_*` Konstanten,
[Zeilen 17–24](LocalGridPlanner.gd:17)):

| Key | Typ | Bedeutung |
|---|---|---|
| `success` | bool | Wurde ein gültiger Umweg gefunden? |
| `path` | `PackedVector3Array` | Welt-Wegpunkte (ohne Startzelle) |
| `goal` | `Vector3` | Letzter Wegpunkt |
| `status` | String | Lesbare Zusammenfassung („front row 4", „blocked start" …) |
| `follow_global` | bool | Alles rot → Avoidance aufgeben, dem globalen Pfad folgen |
| `surface_escape_cooldown` | float | Sekunden, in denen Surface-Escape unterdrückt wird |
| `debug_cells`, `debug_physics_hits` | Array | Nur für Debug-Zeichnung |

---

## 3. Dual-Subdivided 8-Connect Grid (NICHT Hex)

> **Korrektur (2026-04-27):** In früheren Doku-Versionen stand hier „6 echte
> Hex-Nachbarn → keine Treppen". Das war falsch. Test
> `tools/codex_local_grid_topology_test.gd` hat gezeigt: Eine pure 6-Nachbar-
> Variante macht Pfade **38 % länger und 3× kantiger**. Der Code ist *kein*
> Hex — er ist ein dual-subdivided 8-connect-Grid und das ist Absicht.

Der Planner nutzt **„doubled coords"**: jede Zelle ist `Vector2i`, die
Welt-Position folgt aus dem Index:

```
Normale Zelle    Vector2i(x*2,   z*2)        Welt-Offset (x*step,       z*step)
Versetzte Zelle  Vector2i(x*2+1, z*2+1)      Welt-Offset ((x+0.5)*step, (z+0.5)*step)
```

Die versetzten Zellen liegen **diagonal zwischen** den vier Eckzellen einer
Kachel — sie sind **keine Hex-Reihen**, sondern Füllpunkte für feinere
A*-Auflösung in den Diagonalen.

**8 Nachbarn** in `_GRID_NEIGHBORS`:

```
(±1, ±1)             ← 4 diagonale Verbindungen zu den Füllzellen
(±2, 0)              ← 2 axiale X-Verbindungen
(0, ±2)              ← 2 axiale Z-Verbindungen
```

**Warum ALLE 8?**

Mit nur den 4 Diagonalen (echtes Hex-Verhalten) müsste A* auf jeder geraden
Vorwärtsstrecke zwischen zwei Diagonalen zickzackeln. Konkret gemessen für
`step = 0.12 m`, Goal 1.14 m geradeaus:

| Variante      | Waypoints | Pfadlänge | Richtungswechsel |
|---------------|-----------|-----------|------------------|
| 8-connect     | 11        | 1.165 m   | 2                |
| 6-connect     | 20        | 1.612 m   | 6                |

→ Die axialen Verbindungen sind ein **bewusster Trade-off**: max. Single-
Step ist `step` statt `0.71·step`, aber gerade Strecken bleiben gerade und
nicht zickzack.

`step = local_astar_cell_size / local_astar_grid_subdivisions`
`cell_radius = ceil(local_astar_radius / step)` definiert, wie viele
Ringe um den Citizen erzeugt werden.

> **Regression-Schutz:** `tools/codex_local_grid_topology_test.gd` (Test-Key
> `navgrid` in `run_tests.ps1`) prüft nach jeder Änderung, dass die 8-connect-
> Variante objektiv besser bleibt. PR-Reviews, die `_GRID_NEIGHBORS` kürzen
> wollen, müssen den Test mit-anpassen.

---

## 4. Ablauf von `build_detour()`

### Schritt 0 — Vorbereitung ([Z. 47–90](LocalGridPlanner.gd:47))

* Ergebnis-Dict initialisieren (alles auf „failed" gesetzt).
* Frühzeitig abbrechen, wenn keine Welt da ist oder `desired_direction` null.
* `forward = desired_direction.normalized()`, `right` senkrecht dazu.
* `start_surface_kind` per Surface-Ray bestimmen → wenn Citizen auf Straße
  steht, ist `start_needs_escape = true` und der Planner darf auch über
  Straße hinweg planen, bis er wieder auf Gehweg landet.

### Schritt 1 — Pass 1: Surface-Probe für ALLE Zellen ([Z. 97–104](LocalGridPlanner.gd:97))

Ruft `_fill_cell_surface()` für **jede** Zelle in beiden Sub-Gittern
(normal + versetzt). Schreibt:

* `cell_surfaces[cell]` → String wie `KIND_PEDESTRIAN`, `KIND_ROAD` …
* `cell_hit_positions[cell]` → exakter Treffer-Punkt (für Debug + Höhe)

> **Warum zwei Pässe?** Der Road-Buffer im 2. Pass schaut auf Nachbar-Surfaces
> (`_is_cell_within_road_buffer`). Damit das funktioniert, müssen ALLE Surfaces
> *vorher* bekannt sein — sonst wäre die Antwort von der Iterationsreihenfolge
> abhängig.

### Schritt 2 — Pass 2: Physik-Probe + Registrieren ([Z. 107–118](LocalGridPlanner.gd:107))

Ruft `_probe_and_register_cell()` für jede Zelle. Pro Zelle:

1. **Physik-Probe** via `LocalPerception.get_probe_block_info(world_point)`
   — eine `SphereShape3D` wird auf **mehreren Y-Höhen** abgefragt
   (siehe [Höhen-Sondierung](#höhen-sondierung-deine-idee)).
2. **Surface-Blocked?** (`_is_surface_blocked` → Straße bei aktivem
   `local_astar_avoid_road_cells`)
3. **Road-Buffer?** Nachbarzellen prüfen — wenn eine Nachbarn-Zelle Straße
   ist und der Buffer-Radius > 0, ist diese Zelle „nahe Straße".
4. **Filter** ([Z. 400–405](LocalGridPlanner.gd:400)):
   * `physics_blocked` → außer Startzelle: nicht aufnehmen
   * `surface_blocked` → außer Startzelle und nicht im Escape-Modus: nicht aufnehmen
   * `near_road_buffer` oder `physics_near_road` → analog
5. Wenn Zelle „grün" → in `astar` registrieren, ID merken in `point_ids`.

### Schritt 3 — Nachbarn verbinden ([Z. 132–142](LocalGridPlanner.gd:132))

Für jede registrierte Zelle wird mit allen 8 Grid-Nachbarn (sofern auch
registriert) eine **bidirektionale** A*-Kante erzeugt.

Optimierung: `if point_id < neighbor_id` verhindert doppelte Aufrufe von
`connect_points`.

### Schritt 4 — Kandidaten sammeln ([Z. 145–192](LocalGridPlanner.gd:145))

Iteriert über `point_ids` und sammelt alle Zellen, die:

* nicht die Startzelle sind,
* keine Straße sind,
* in der **vorderen Hälfte** des Kreises liegen (`offset.y > 0`)
  — bzw. bei `start_needs_escape` einfach weit genug von `start_cell`,
* Mindestabstand zum Rand haben (`>= radius - cell_size*1.5`).

Pro Kandidat wird gemerkt:

* `path` → 2D-A*-Pfad von Start zu Kandidat (`astar.get_point_path`)
* `offset` → Welt-Versatz (Vector2)
* `reference_distance` → wie weit ist der Kandidat vom **globalen Pfad** weg?
  (siehe `_distance_to_global_path_ahead`, [Z. 306–316](LocalGridPlanner.gd:306))
* `path_length` → 2D-Länge des A*-Pfades
* `surface`, `near_road`

`front_y` = der größte gefundene Y-Offset (= „Frontreihe") und
`left_open` = wurde mind. eine Zelle links gefunden?

### Schritt 5 — Tier-Auswahl ([Z. 207–255](LocalGridPlanner.gd:207))

**Hierarchie**:

1. **Road-frei in der Frontreihe?** Ja → andere Kandidaten verwerfen.
2. **`prefer_right_when_left_open` aktiv UND links offen?** Ja → bevorzuge
   Kandidaten mit `offset.x >= 0` (Rechtsverkehr / Gegenverkehr ausweichen).
3. **Score**: `reference_distance + path_length * faktor`
   * `faktor = 0.25` (Escape) oder `0.1` (normal)
   * `+ near_road_penalty` falls Nachbar-Straße
   * `- offset.x * 0.05` falls `prefer_right` (drückt nach rechts)

Der Kandidat mit **kleinstem Score** gewinnt.

### Schritt 6 — Welt-Pfad bauen ([Z. 266–273](LocalGridPlanner.gd:266))

Der A*-Pfad ist 2D (Offset-Koords). Wir konvertieren zurück nach Welt-Raum
über `_world_from_offset(origin, right, forward, off)`:

```gdscript
point = origin + right * off.x + forward * off.y
point.y = origin.y   # ← Höhe wird AUF Citizen-Höhe geklemmt!
```

Den ersten Wegpunkt (= Startzelle) lassen wir weg, da dort der Citizen
schon steht.

---

## 5. Höhen-Sondierung (deine Idee)

Du hast recht: aktuell wird die **Y-Höhe des Wegpunkts hart auf
`origin.y` gesetzt** ([Z. 295](LocalGridPlanner.gd:295)). Der Planner ist
damit **2D auf der Citizen-Höhe**.

### Was es heute schon gibt

`LocalPerception.get_probe_block_info()` ([LocalPerception.gd:144](LocalPerception.gd:144))
sondiert pro Zelle **mehrere Höhen** mit einer Kugel:

```gdscript
for probe_y_offset in _ctx.config.get_probe_heights():
	probe_position.y = owner_pos.y + probe_y_offset
	# SphereShape3D-Query auf collision_mask = owner mask
```

`CitizenConfig.get_probe_heights()` ([CitizenConfig.gd:87](CitizenConfig.gd:87))
liefert eine **lineare Rampe** von `local_astar_probe_min_height` bis
`local_astar_probe_max_height` mit `local_astar_probe_height_steps` Schritten.

Default ist üblicherweise **Knie + Hüfte + Brust** — also wie du
beschreibst: **von Boden bis halbe Citizen-Größe**.

Außerdem nutzt `is_obstacle_below_jump_height()`
([LocalPerception.gd:101](LocalPerception.gd:101)) eine **Zwei-Probe-Heuristik**
(near-Down-Ray + far-Sphere bei Sprunghöhe), um zu entscheiden, ob ein
niedriges Hindernis übersprungen werden kann statt umgangen.

### Was deine Idee zusätzlich bringen würde

Deine Beschreibung:

> kreisweise scannen von halb Größe von Citizen bis zu Fuß (vllt bissel
> niedriger um Boden zu erkennen), um Objekte und deren Höhe zu erkennen,
> um globalem Pfad sauber zu folgen.

Heute funktioniert das **pro Probe-Punkt** schon (mehrere Y-Stufen).
Aber die **Höhe wird nicht in die Pfad-Y gespeichert**. Die Pfade liegen
alle flach auf `origin.y`. Das reicht solange:

* Boden flach ist
* Hindernisse als „blockiert / frei" reichen
* Sprünge per separatem `JumpController` behandelt werden

**Dein Vorschlag = Höhen-bewusste Pfade.** Dafür müsste man:

1. In `_probe_and_register_cell()` **zusätzlich zur Sphere-Probe einen
   Down-Ray** schießen, um die echte Boden-Y der Zelle zu finden
   (entspricht `probe_surface()` — wir haben sie sogar in
   `cell_hit_positions` schon zur Hand!).
2. Die Boden-Y in `point_ids` mit speichern (Dictionary erweitern oder
   parallele Map).
3. In `_world_from_offset()` einen Overload nutzen, der die gespeicherte
   Y verwendet statt `origin.y`.
4. **Steigungs-Check** zwischen Nachbarzellen: wenn `|y_a - y_b| > max_step`,
   die A*-Kante NICHT verbinden (oder mit hohen Kosten).
5. **Höhen-Layering**: die schon vorhandene Probe-Höhen-Rampe könnte man
   nutzen, um **Tunnel / Brücken** (= Zelle ist überdacht aber unten frei)
   getrennt von Wänden zu erkennen.

### Konkrete Anknüpfungspunkte im Code

| Ort | Was tun |
|---|---|
| `_fill_cell_surface()` ([Z. 347](LocalGridPlanner.gd:347)) | Speichert bereits den Boden-Hit. `cell_hit_positions[cell].y` ist die echte Boden-Y. |
| `_probe_and_register_cell()` ([Z. 361](LocalGridPlanner.gd:361)) | Hier zusätzlich `cell_y = cell_hit_positions[cell].y` in eine neue Map `cell_heights` schreiben. |
| Nachbar-Verbindung ([Z. 132](LocalGridPlanner.gd:132)) | Vor `connect_points` Höhenunterschied prüfen → wenn zu groß: skip. |
| `_world_from_offset()` ([Z. 292](LocalGridPlanner.gd:292)) | Variante mit Y-Override schreiben, damit der zurückgegebene Pfad die echte Boden-Höhe trägt. |
| Pass 2 → Filter ([Z. 400](LocalGridPlanner.gd:400)) | Falls Boden tiefer als Citizen-Position − max-Falltiefe → zusätzlich blockieren (Klippen-Schutz). |

> **Achtung:** `CitizenConfig.debug_draw_cell_heights = true` deutet darauf
> hin, dass es einen Visualizer für Zellen-Höhen schon gibt — vermutlich
> wird der Wert irgendwo gesammelt, aber nicht für die Pfadwahl genutzt.
> Lohnt sich, zuerst das Debug-Drawing zu suchen, bevor du parallel etwas
> baust.

---

## 6. Wichtige Helper-Funktionen kurz erklärt

| Funktion | Zweck |
|---|---|
| `_cell_id()` ([Z. 287](LocalGridPlanner.gd:287)) | Vector2i → eindeutige int für `AStar2D` |
| `_world_from_offset()` ([Z. 292](LocalGridPlanner.gd:292)) | 2D-Offset (right, forward) → Welt-Vector3 (Y geklemmt) |
| `_distance_to_global_path_ahead()` ([Z. 306](LocalGridPlanner.gd:306)) | Plan-Distanz zum nächsten globalen Segment ab `path_index` |
| `_planar_distance_to_segment()` ([Z. 325](LocalGridPlanner.gd:325)) | XZ-Punkt-zu-Segment-Distanz (Y ignoriert) |
| `_is_surface_blocked()` ([Z. 341](LocalGridPlanner.gd:341)) | Konfig-getrieben: Straße = blockiert, alles andere = frei |
| `_is_cell_within_road_buffer()` ([Z. 412](LocalGridPlanner.gd:412)) | Grid-BFS bis `road_buffer_cells` Tiefe — sucht Straße in der Nähe |
| `_neighbor_offsets_in_radius()` ([Z. 426](LocalGridPlanner.gd:426)) | Alle Grid-Offsets in einem N-Ring (BFS) |

---

## 7. TL;DR

* **Eingabe**: Wunschrichtung + globaler Pfad
* **Aufbau**: doubled-Coord 8-connect-Gitter (kein echtes Hex, siehe §3) um den Citizen, A*-fähig
* **Pro Zelle**: 1× Surface-Ray (Boden-Klassifikation) + 1× Sphere-Probe
  (Physik, mehrere Y-Höhen)
* **Filter**: Straße, Road-Buffer, Physik-Block → rot. Sonst grün → A*-Knoten.
* **Auswahl**: Kandidat in der Frontreihe mit kleinstem
  `Distanz-zu-globalem-Pfad + α·Pfadlänge` gewinnt.
* **Ausgabe**: Welt-Pfad auf Citizen-Höhe (2D in der Praxis).
* **Deine Höhen-Idee**: Mehrhöhen-Probes existieren schon in `LocalPerception`;
  was fehlt ist, die echte Boden-Y in die Pfad-Y zu propagieren und
  Höhenunterschiede in die A*-Kostenfunktion einzubauen.
