# AI-Dialog mit Ollama

Diese Datei beschreibt den aktuellen Player-zu-NPC-Dialogpfad. Kurzfassung:
Der Dialog nutzt Ollama, wenn die lokale Runtime bereit ist und ein passendes
Modell verfuegbar ist. Wenn nicht, faellt das System auf Template-Antworten
zurueck, damit das Spiel nicht haengt.

## Laufzeitpfad

1. `Simulation/Conversation/CitizenConversationManager.gd`
   - verwaltet aktive Player-Dialog-Sessions
   - sammelt Citizen-Zustand, aktuelle Player-Nachricht, letzte Turns,
     bekannte Orte, nahe Orte, Ziel, Needs und Grounding-Regeln
   - erkennt klare Gameplay-Intents vor dem LLM, z. B. soziale Einladungen
     zu Restaurant, Park oder Kino
   - startet echte `SocialVisitAction`, wenn eine Einladung eindeutig und
     nutzbar ist

2. `Simulation/AI/LocalDialogueRuntimeService.gd`
   - prueft lokale Ollama-Erreichbarkeit
   - startet optional die bevorzugte lokale Runtime aus `AI/llama`
   - sucht Modelle in der Reihenfolge aus `config/dialogue_runtime.json`
   - baut den finalen Prompt fuer `player_npc`
   - fragt Ollama an oder nutzt Template-Fallback

3. `Scenes/DebugPanel.gd` und `Simulation/UI/SimulationInteractionController.gd`
   - zeigen Start/End Dialog, Status, Log und Eingabe
   - leiten Player-Zeilen an den ConversationManager weiter

## Wann ist es wirklich Ollama?

Im HUD steht der grobe AI-Status:

- `AI: Ready`: Runtime/Modell ist nutzbar
- `AI: Model missing`: kein passendes lokales Modell gefunden
- `AI: Fallback active`: Template-Fallback statt Modellantwort

Im Log ist es genauer. Sieh in `ai.log` nach:

- `source=ollama` bedeutet: Antwort kam vom lokalen Modell
- `source=template` oder `source=template_fallback` bedeutet: kein Modell,
  Queue voll, Timeout oder absichtlicher Fallback

Auch bei `source=ollama` ist die Antwort nicht garantiert korrekt. Das LLM
ist nur Textgenerierung. Gameplay-relevante Absichten muessen vor dem LLM
erkannt und als Spielaktion ausgefuehrt werden.

## Warum kann Ollama den Kontext falsch deuten?

Ein lokales kleines Modell bewertet den kompletten Prompt wahrscheinlichkeits-
basiert. Es hat keine harte Pflicht, die neueste Player-Zeile immer korrekt
zu priorisieren. Wenn der vorherige NPC-Satz stark `essen`, `Restaurant` oder
`Kaffee` enthaelt und die neue Player-Zeile Tippfehler hat, kann das Modell
auf den alten Kontext zurueckfallen.

Deshalb gilt im Projekt:

- aktuelle Player-Message hat hoechste Prioritaet
- klare Einladungen werden regelbasiert erkannt
- das LLM darf formulieren, aber keine Gameplay-Absicht ersetzen
- bekannte und nahe Orte kommen explizit in den Prompt
- der Prompt verbietet neue erfundene Orte/Routen

## Soziale Einladungen

Der ConversationManager erkennt Saetze wie:

- `Lass uns essen gehen.`
- `Komm mit ins Restaurant.`
- `Willst du mit mir in den Park gehen?`
- `ne wenns im Park gehen willst du mir mir gehen?`
- `Kommst du mit in den Park?`
- `Wollen wir ins Kino gehen?`

Wenn ein passendes Ziel existiert und beide Teilnehmer es nutzen koennen,
startet das System eine echte `SocialVisitAction` fuer Player und NPC. Dann
kommt die Antwort nicht vom LLM, sondern aus einer kontrollierten Annahmezeile,
damit das Ziel nicht von Park zu Restaurant oder Kaffee driftet.

## Konfiguration

Wichtige Dateien:

- `config/dialogue_runtime.json`
  - Ollama-Start, Modellpraeferenzen, Prompt-Felder, Prompt-Regeln, Fallback
- `config/conversation_rules.json`
  - Dialog-Reichweiten, Session-Memory, Commitments, Social-Gain, Auto-Close

Wichtige Profile:

- `player_npc`: direkte Player-zu-NPC-Gespraeche
- `npc_npc`: generierte NPC-zu-NPC-Gespraeche / Barks

## Tests ohne UI, Ollama und Modell

Die wichtigsten Intent-Tests laufen headless und rufen nur Code auf:

```powershell
powershell -ExecutionPolicy Bypass -Command "& { .\run_tests.ps1 -Only @('runtime') }"
```

Relevante Tests in `tools/codex_runtime_lod_conversation_test.gd`:

- `player_dialog_invitation_sentence_parser_cases`
  - prueft feste Player-Saetze direkt gegen Parser-Regeln
- `player_dialog_invitation_starts_shared_park_visit_from_player_wording`
  - prueft den Screenshot-Fall: Park-Einladung darf nicht zu Restaurant/Kaffee
    driften
- `player_dialog_invitation_starts_shared_restaurant_visit`
  - prueft Restaurant-Einladung als echte SocialVisitAction
- `player_dialog_request_uses_json_profile_options`
  - prueft, dass Prompt-Felder/Regeln aus JSON in den Request kommen

Diese Tests brauchen kein UI und kein Ollama. Sie sichern die Gameplay-Schicht
ab, bevor ein lokales Modell ueberhaupt antworten darf.
