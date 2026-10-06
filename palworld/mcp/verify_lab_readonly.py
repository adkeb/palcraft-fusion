"""Read-only integration check against the isolated real BridgeLab server."""
import json
from pathlib import Path
import subprocess
import sys


def main():
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "lab-readonly-verification", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "palworld_status", "arguments": {}}},
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "palworld_players", "arguments": {}}}]
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("server.py")),
        "--bridge-script", r"D:\PalworldServer-LAN\BridgeLab\Invoke-Bridge.ps1"],
        input=("\n".join(json.dumps(m) for m in messages) + "\n").encode(),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45, check=True)
    assert not result.stderr, "Unexpected MCP stderr"
    replies = [json.loads(line) for line in result.stdout.decode("utf-8").splitlines()]
    assert len(replies) == 4
    tools = [tool["name"] for tool in replies[1]["result"]["tools"]]
    assert {"palworld_capabilities", "palworld_status", "palworld_players"}.issubset(tools)
    for reply in replies[2:]:
        assert not reply["result"]["isError"], reply
    info = json.loads(replies[2]["result"]["content"][0]["text"])
    players = json.loads(replies[3]["result"]["content"][0]["text"])
    assert isinstance(info, dict) and info.get("version")
    assert isinstance(players.get("players"), list)
    print(json.dumps({"ok": True, "transport": "MCP stdio -> SSH -> PowerShell -> lab REST 8322",
        "version": info["version"], "server_name": info.get("servername"),
        "player_count": len(players["players"]), "available_tools": tools}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
