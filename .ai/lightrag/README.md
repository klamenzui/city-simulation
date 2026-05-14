# LightRAG Preparation

LightRAG is prepared but not installed in this workspace because Python and `uv` are not available on this machine yet.

## Recommended Setup

1. Install `uv` for Windows.
2. Install the LightRAG API server:

```powershell
uv tool install "lightrag-hku[api]"
```

3. Copy `.env.example` to `.env` and fill in the chosen LLM and embedding provider.
4. Start the server from this folder:

```powershell
lightrag-server --host 127.0.0.1 --port 9621 --workspace city-sim --working-dir .\rag_storage --input-dir .\inputs
```

5. Verify:

```powershell
Invoke-RestMethod http://localhost:9621/health
```

## MCP Bridge Status

No LightRAG MCP bridge is enabled by default. The official LightRAG project documents the API server, but the MCP bridge packages I found are community packages. Review package source and pin versions before enabling one in Codex.
