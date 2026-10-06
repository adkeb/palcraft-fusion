"""Opt-in integration check against the Windows mcp-test mock, never a game."""
import json
from pathlib import Path
import subprocess
import sys
import uuid


def main():
    request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "live-control-integration-test", "version": "1"}}}
    messages = [request, {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "palworld_status", "arguments": {}}},
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "palworld_players", "arguments": {}}},
        {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "palworld_storage_apply", "arguments": {
            "plan_id": "unimplemented", "expected_revision": "unimplemented", "idempotency_key": str(uuid.uuid4())}}}]
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("server.py")),
        "--bridge-script", r"D:\PalworldServer-LAN\BridgeLab\mcp-test\Test-Stdio.ps1"],
        input=("\n".join(json.dumps(m) for m in messages) + "\n").encode(),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=True)
    assert not result.stderr, "Unexpected MCP stderr"
    replies = [json.loads(line) for line in result.stdout.decode("utf-8").splitlines()]
    assert len(replies) == 5, "Notifications must not receive responses"
    assert replies[0]["result"]["protocolVersion"] == "2025-06-18"
    assert [tool["name"] for tool in replies[1]["result"]["tools"]] == [
        "palworld_capabilities", "palworld_acceptance_status", "palworld_status", "palworld_players"]
    assert json.loads(replies[2]["result"]["content"][0]["text"])["servername"] == "箱子"
    assert json.loads(replies[3]["result"]["content"][0]["text"])["players"] == []
    assert replies[4]["result"]["isError"]
    assert json.loads(replies[4]["result"]["content"][0]["text"])["error"]["code"] == "unsupported"
    print(json.dumps({"ok": True, "transport": "MCP stdio -> SSH -> Windows PowerShell 5.1 mock",
        "checks": ["initialization", "JSON-only stdout", "verified-only tools", "UTF-8 Chinese text",
                   "empty arrays", "unverified mutation rejected"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
