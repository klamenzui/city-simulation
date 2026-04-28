# Claude — Regeln für diesen Vault

Dies ist der zentrale Wissens-Vault. **Jedes** Gespräch — egal welches Thema oder Projekt — soll hier seine Spuren hinterlassen, sofern es Substanz hat.

## Grundprinzipien
- Sprache: Deutsch.
- Immer mit dem Vault arbeiten. Wenn ein Thema neu ist und Substanz hat: in den Vault aufnehmen, nicht nur antworten und vergessen.
- Niemals außerhalb von `C:\dev\projects\ai_brain\AI_brain` schreiben (technisch durch MCP-Sandbox blockiert, hier zur Klarheit).
- Niemals Notizen löschen oder umbenennen ohne expliziten Auftrag. Veraltetes wandert nach `50_Archive/`.
- Bei Unklarheit (welcher Ordner? welcher MOC? Notiz oder Quelle?) **nachfragen**, nicht raten.

## Ordnerlogik (Kurzfassung — Details im jeweiligen README)
- `00_Inbox/` — Eingang. Unfertiges, Ungeordnetes. Wird regelmäßig geleert.
- `10_Notes/` — Permanente atomare Notizen. **Flach.** Keine Unterordner.
- `20_Sources/` — Literatur-/Quellennotizen.
- `30_Projects/` — Aktive Projekte mit Ziel und (idealerweise) Enddatum.
- `40_Areas/` — Dauerthemen ohne Enddatum.
- `50_Archive/` — Abgeschlossen / inaktiv.
- `_Maps/` — MOCs (Maps of Content), thematische Einstiegsseiten.
- `_Templates/` — Vorlagen für neue Notizen.
- `_Attachments/` — Bilder, PDFs, Anhänge.

## Notiztypen

| Typ | Wo | Wann |
|---|---|---|
| Atomare Notiz | `10_Notes/` | Eine eigenständige, wiederverwendbare Idee |
| Quelle | `20_Sources/` | Buch, Artikel, Video, Podcast, Gespräch |
| MOC | `_Maps/` oder Projektordner | Einstiegsseite zu einem Thema |
| Projekt-Notiz | `30_Projects/<projekt>/` | Nur projektspezifisch (Plan, Status) |
| Bereichs-Notiz | `40_Areas/<bereich>/` | Nur bereichsspezifisch |

## Regeln für neue Notizen
1. **Template aus `_Templates/` verwenden.** Frontmatter komplett ausfüllen.
2. **Atomar.** Eine Idee = eine Notiz. Lieber drei kurze als eine lange.
3. **Mindestens ein eingehender Wikilink.** Eine Notiz ohne Verbindung ist eine Waise und geht verloren. Aus passendem MOC oder verwandter Notiz verlinken.
4. **Wikilinks `[[...]]` bevorzugen, Tags sparsam.** Tags sind Filter (`#status/offen`), keine Themen-Hierarchie.
5. **Dateinamen für `10_Notes/`:** `YYYYMMDDHHmm – Titel.md` (z. B. `202604251530 – Prompt Caching reduziert Latenz.md`). In allen anderen Ordnern reicht der sprechende Titel.

## Workflow: Neues Projekt taucht im Gespräch auf
1. Ordner anlegen: `30_Projects/<Projektname>/`
2. Darin `MOC – <Projektname>.md` als Einstiegspunkt (Ziel, Status, Links).
3. Im Vault-Index `_Maps/MOC – Index.md` unter "Aktive Projekte" verlinken.
4. Neue Erkenntnisse als atomare Notizen in `10_Notes/` ablegen, vom Projekt-MOC verlinken — **nicht** im Projektordner vergraben. Sonst geht das Wissen beim Archivieren verloren.
5. Projekt fertig → Projektordner nach `50_Archive/` verschieben. Atomare Notizen bleiben in `10_Notes/`.

## Workflow: Neues Thema im Gespräch
1. Flüchtig (Frage, kurze Antwort) → keine Notiz.
2. Substanziell (Erkenntnis, Entscheidung, Recherche) → in `00_Inbox/` ablegen, oder direkt in `10_Notes/`, falls klar einsortierbar.
3. Passender MOC existiert → dort verlinken. Sonst und Thema kehrt wieder → MOC in `_Maps/` anlegen und im Index eintragen.

## Was Claude nicht tut
- Notizen löschen oder umbenennen ohne Auftrag.
- Ordnerstruktur ändern ohne Rückfrage.
- Außerhalb des Vaults schreiben.
- Notizen ohne mindestens einen Wikilink anlegen.
- Tags wuchern lassen — vor neuem Tag prüfen, ob ein vorhandener passt.
- Quellen wörtlich kopieren — eigene Worte, Zitate kennzeichnen.
