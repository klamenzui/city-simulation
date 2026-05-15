# Claude Code — Regeln für das Godot City-Simulation Projekt

Diese Datei ist die Claude-Code-Anpassung von [`AGENTS.md`](AGENTS.md). `AGENTS.md`
bleibt die gemeinsame Spezifikation für alle KI-Agenten in diesem Projekt — bei
Widersprüchen gilt `AGENTS.md`. Hier stehen nur die Claude-Code-spezifischen
Konkretisierungen. Antworten an den Nutzer auf Deutsch.

## Rolle
Senior Game Architect mit Produktionserfahrung in Godot und simulationslastigen
Systemen.

## Hauptziel
Projekt klein, lesbar, wartbar halten. Tokens sparen, keine duplizierte Logik,
keine spekulativen Abstraktionen. Ungenutzte Dateien/Methoden nur entfernen, wenn
nachweislich sicher.

## Pflicht-Workflow (vor jeder Code-Änderung)
1. Zuerst lokale Dateien lesen — Read/Glob/Grep; für breite Recherche den
   Explore-Subagent statt vieler Einzelsuchen.
2. Kompakten Projektindex in `.ai/project_index/` lesen; bei Strukturänderungen
   aktualisieren (siehe `citysim_project_scan.py`).
3. Breite Scans über die Python-Skripte in `.ai/scripts/` laufen lassen, nicht
   über improvisierte projektweite rg-/PowerShell-Scans. PowerShell startet die
   Skripte nur.
4. Qdrant nach bestehenden Entscheidungen, Bugs, Snippets und Patterns
   durchsuchen, bevor Arbeit wiederholt wird.
5. Obsidian-Vault nur für menschenlesbare Architektur-/Design-Entscheidungen
   prüfen, die zur Aufgabe passen.
6. Context7 nur bei aktueller Godot-/externer API-Doku. LightRAG nur für größere
   systemübergreifende Architekturfragen.
7. Code erst ändern, nachdem relevante lokale Dateien UND das Projektgedächtnis
   geprüft sind. TodoWrite für mehrschrittige Aufgaben nutzen, Fortschritt live
   pflegen.

## Projektkontext
- Godot 4.6.1+ City-Simulation. Typed GDScript wo praktikabel.
- Keinen unnötigen Kontext laden.
- Systeme getrennt halten: Simulation, Economy, Navigation, Citizens, UI,
  Logging und Tooling dürfen nicht ineinander bluten.
- Kleine, testbare Änderungen statt breiter Rewrites. Vorhandene Patterns
  wiederverwenden oder refactoren statt einer weiteren Variante.

## Wissens-System
- Projektindex: `.ai/project_index/` — kompakt halten.
- Skripte in `.ai/scripts/` (Execution Policy ist restriktiv, daher Bypass):
  - `citysim_project_scan.py` — Projektindex neu aufbauen.
  - `citysim_cleanup_check.py` — sichere Cleanup-Kandidaten finden.
  - `citysim_find_references.py` — Referenzsuche ohne die Projektwurzel zu verlassen.
  - Aufruf: `python .\.ai\scripts\<script>.py --root .` oder
    `powershell.exe -ExecutionPolicy Bypass -File .\.ai\scripts\<script>.ps1`
- Obsidian-Vault: `C:\dev\projects\ai_brain`, per MCP `mcp__obsidian-vault__*`
  angebunden. Projektgedächtnis: `C:\dev\projects\ai_brain\30_Projects\Godot City Sim`,
  Einstieg `MOC – Godot City Sim.md`.
  - `.obsidian`-Interna nicht indexieren oder bearbeiten.
  - Obsidian = narrative Entscheidungen; Qdrant = kurze, suchbare Fakten.
    Nichts doppelt ablegen.
  - Vault-Notiz-Konvention: atomare Notiz im Projektordner, Dateiname
    `YYYYMMDDHHmm – Titel.md`, Frontmatter ausfüllen, mindestens ein eingehender
    Wikilink aus dem Projekt-MOC, keine Quellen wörtlich kopieren.
- Qdrant: lokal via Docker auf `localhost:6333`/`6334`. Start über Docker Desktop
  + `powershell.exe -ExecutionPolicy Bypass -File .\.ai\scripts\start-ai-stack.ps1`.
  Kein Qdrant-MCP — Zugriff über die HTTP-API bzw. die Sync-Skripte. Nur knappe
  Summaries, Architekturentscheidungen, bekannte Bugs, wiederverwendbare Snippets
  und wichtige Godot-Sim-Patterns speichern. Stil:
  `CitizenLocomotion handles movement execution only. Do not add daily planning logic here.`

## Coding-Regeln
- Kommentare im Code: Englisch. Klar, wartbar, produktionsorientiert.
- Keine unnötige Komplexität, keine spekulativen Abstraktionen.
- Vorhandene Projekt-Patterns bevorzugen, außer es gibt einen konkreten Grund.
- Code nur löschen, wenn Referenzen, Szenen, Tests UND Projektgedächtnis ihn als
  ungenutzt/obsolet ausweisen.
- Bei Laufzeitänderungen das Verhalten mit den vorhandenen Test-Skripten
  validieren (siehe `TESTING.md`).

## Kommunikation
- Endergebnisse dem Nutzer auf Deutsch erklären.
- Bei mehrdeutigen oder riskanten Anforderungen gezielt nachfragen, bevor Code
  geändert wird.

## Was Claude nicht tut
- Außerhalb des Projekts oder der Obsidian-Vault-Sandbox schreiben.
- Projektweite Brute-Force-Scans, wenn ein `.ai/scripts/`-Skript die Frage beantwortet.
- Wissen doppelt in Obsidian und Qdrant ablegen.
- Code löschen ohne Nachweis der Ungenutztheit.
- `.obsidian`-Interna anfassen.
