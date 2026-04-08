# Local AI Runtime

Diese Ordnerstruktur ist fuer eine portable lokale KI-Runtime gedacht:

- `AI/llama`: lokale Runtime-Binaries wie `ollama.exe`
- `AI/models`: lokale Modellablage ueber `OLLAMA_MODELS`
- `AI/runtime`: Logs, temporaere Downloads und Runtime-Zustand
- `AI/profiles`: Ollama-Modelfile-Templates fuer spielinterne Dialog-Profile

Der Godot-Runtime-Service bevorzugt zuerst `AI/llama/ollama.exe` und faellt danach auf globale Installationen zurueck.

Zum Setup gibt es `tools/install_portable_ollama.ps1`.
Die Dialog-Profile `npc-player` und `npc-overheard` werden ueber `tools/create_local_dialogue_profiles.ps1` aus einem Basis-Modell erzeugt.
