Palworld live-control MCP adapter
================================

State: adapter implemented and unit-tested. No in-game write capability is
claimed by this code. A separately deployed backend must implement and verify
each operation against the running Palworld build before it becomes available.

Requirements
- Python 3.9 or later, standard library only.
- Existing authenticated OpenSSH alias 5090. No passwords are read by this code.
- A fixed PowerShell bridge script on the target PC; that script must read a
  complete UTF-8 request from stdin and return one JSON response on stdout.

Run as an MCP stdio process
  python3 /absolute/path/to/mcp/server.py

Test against the isolated lab backend
  python3 /absolute/path/to/mcp/server.py --bridge-script 'D:\PalworldServer-LAN\BridgeLab\Invoke-Bridge.ps1'

Read-only diagnostic call
  python3 /absolute/path/to/mcp/server.py --bridge-script 'D:\PalworldServer-LAN\BridgeLab\Invoke-Bridge.ps1' --call palworld_capabilities

Run local tests (no SSH or game changes)
  cd /absolute/path/to/mcp
  python3 -m unittest -v

Protocol and schemas
- protocol.json specifies the SSH request/response envelope and backend rules.
- tool-schemas.json is generated from the exact schemas in server.py.
- The official MCP stdio transport is newline-delimited JSON-RPC 2.0:
  https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- Lifecycle negotiation follows:
  https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle
- Supported MCP versions: 2025-06-18, 2025-03-26, 2024-11-05. Unsupported newer
  client versions negotiate 2025-06-18; the client may disconnect if unsupported.

Capability gating
- palworld_capabilities and palworld_acceptance_status are always listed.
- palworld_acceptance_status reads only the fixed acceptance-status.json beside
  server.py. It makes no SSH/REST/game calls, takes no path arguments, and is
  explicitly a dated local evidence snapshot, NOT LIVE server health. Its
  generated_utc, content SHA256, evidence-file SHA256 references and age prevent
  treating file-read time as verification time. Missing/invalid evidence errors
  clearly; its records never enable backend capabilities.
- Game tools are listed only when backend supported and verified are both
  boolean true, and read_only matches the adapter's method definition.
- Writable operations also require a verified operations.get capability.
- Capabilities are refreshed before every game tool call. No stale cached flag can
  authorize an operation after capabilities change.
- No arbitrary shell, PowerShell, Lua, file-path or console-execution tool exists.
- Backend capabilities are data about tests, not a substitute for backend
  implementation, authorization, game-thread safety or transaction validation.

Plans and writes
- Storage/build/worker changes first produce an immutable, expiring plan.
- Apply requires plan_id, expected_revision and idempotency_key.
- Backend must recheck current state, normal placement rules and materials.
- Build previews currently accept exactly one structure, a real online player_uid,
  guild_id, base_id and an existing support_model_id. Pitch and roll must be zero;
  only yaw is accepted. Supported build IDs are enforced by the verified runtime.
- Storage excludes player inventories, feed boxes and production queues.
- Backend must preserve item quantities, identities and dynamic metadata.
- A write timeout is explicitly an unknown outcome. The adapter never retries.
  Query operations.get with the returned request_id; retain the original
  idempotency_key if retrying the same operation after backend reconciliation.
- Neither this adapter nor its tests stop the game, edit saves, install mods,
  change Codex settings or activate currently unimplemented game operations.

Current tests cover initialization, clean stdio framing, verified-only tool
discovery, refreshed capability gates, unknown-method rejection, strict input
validation, fixed SSH command/data separation, timeout outcome reporting,
response correlation and avoiding stderr/credential leakage.

Windows lab backend
- Invoke-Bridge.ps1 defaults exclusively to BridgeLab and private REST port 8322.
  It reads the lab INI credential internally and never returns it.
- Lua metadata: rpc/capabilities.json with protocol_version:1,
  server_instance_id UUID, heartbeat_utc ISO UTC, and capability records.
  Heartbeat older than 10 seconds or more than 2 seconds ahead is rejected.
- Requests: rpc/request.json. Replies: rpc/responses/<request_id>.json.
  Both sides must publish files by a temporary write followed by atomic rename.
  Lua must delete the consumed request and reject expired requests before action.
- The PowerShell adapter clamps the request deadline to 25 seconds. It holds a
  named mutex while submitting/waiting, never overwrites an outstanding request,
  and never retries timed-out writes. Lua owns actual game operations and their
  persistent idempotency/transaction logic.
- Test-Bridge.ps1 runs isolated mock-file tests on Windows PowerShell 5.1.
- Test-Stdio.ps1 provides fake REST replies for encoding/transport tests only.
- verify_mock_stdio.py checks the complete MCP -> SSH -> PS5.1 mock path.
- Test files belong in BridgeLab/mcp-test only, not the live RPC directory.
- Production use requires an explicitly configured production context/port and
  re-verification. Copying the script alone does not turn lab defaults into
  production settings.

Deployment note
Connect an MCP client using its own supported configuration mechanism. This
directory intentionally does not modify a client configuration. Default backend
is D:\PalworldServer-LAN\LiveControl\Invoke-Bridge.ps1; use --bridge-script for
the isolated BridgeLab until integration testing has passed.

Local acceptance snapshot
- Read without contacting the server:
  python3 /absolute/path/to/mcp/server.py --call palworld_acceptance_status
- Snapshot contains production storage evidence, limited Lab worker acceptance
  and unavailable Lab building/crash status. Read its date and limitations.
- The current snapshot records read-only v3 as partial-client-unavailable with
  three successful read samples, zero gameplay mutations and zero construction
  attempts. It does not claim full construction or worker restart acceptance.
- To regenerate from local research evidence after a reviewed status change:
  python3 work/palworld-live/research/refresh-acceptance-status.py
  This writes the local mcp snapshot only; it never deploys or changes a running
  MCP configuration, remote RPC script or game mod.
