import io
import json
import copy
from pathlib import Path
import subprocess
import unittest
import tempfile
import datetime as dt
import uuid

import server


class FakeBridge:
    def __init__(self, capabilities=None):
        self.manifest = {"bridge_version": "test", "game_version": "test",
                         "server_instance_id": str(uuid.uuid4()), "capabilities": capabilities or {}}
        self.calls = []

    def call(self, method, params):
        self.calls.append((method, params))
        if method == "capabilities":
            return self.manifest
        return {"method": method, "params": params}


def capability(read_only=True, verified=True):
    return {"supported": True, "verified": verified, "read_only": read_only}


class ProtocolTests(unittest.TestCase):
    def initialized(self, bridge=None):
        instance = server.McpServer(server.Adapter(bridge or FakeBridge()))
        reply = instance.handle({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}})
        self.assertEqual(reply["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(reply["result"]["capabilities"], {"tools": {"listChanged": False}})
        self.assertIsNone(instance.handle({"jsonrpc": "2.0", "method": "notifications/initialized"}))
        return instance

    def test_initialization_and_verified_tools_only(self):
        bridge = FakeBridge({"status": capability(), "storage.apply": capability(False, False),
                             "players": {"supported": "true", "verified": True, "read_only": True},
                             "run_shell": capability(False)})
        instance = self.initialized(bridge)
        result = instance.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        self.assertEqual([t["name"] for t in result["result"]["tools"]],
                         ["palworld_capabilities", "palworld_acceptance_status", "palworld_status"])

    def test_tools_require_initialized_notification(self):
        instance = server.McpServer(server.Adapter(FakeBridge()))
        response = instance.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
        self.assertEqual(response["error"]["code"], -32002)

    def test_unknown_tool_or_unverified_write_never_forwards(self):
        bridge = FakeBridge({"storage.apply": capability(False, False)})
        adapter = server.Adapter(bridge)
        for name, args in [("run_shell", {}), ("palworld_storage_apply", {
                "plan_id": "p1", "expected_revision": "r1", "idempotency_key": str(uuid.uuid4())})]:
            with self.assertRaises(server.BridgeError) as caught:
                adapter.call_tool(name, args)
            self.assertEqual(caught.exception.code, "unsupported")
        self.assertEqual([method for method, _ in bridge.calls], ["capabilities"])

    def test_write_requires_recovery_and_every_apply_field(self):
        bridge = FakeBridge({"storage.apply": capability(False)})
        adapter = server.Adapter(bridge)
        self.assertEqual(len(adapter.list_tools()), 2)
        with self.assertRaises(server.BridgeError):
            adapter.call_tool("palworld_storage_apply", {"plan_id": "p1"})
        bridge.manifest["capabilities"]["operations.get"] = capability()
        args = {"plan_id": "p1", "expected_revision": "r1", "idempotency_key": str(uuid.uuid4())}
        self.assertEqual(adapter.call_tool("palworld_storage_apply", args)["method"], "storage.apply")

    def test_capabilities_refreshed_before_each_call(self):
        bridge = FakeBridge({"status": capability()})
        adapter = server.Adapter(bridge)
        self.assertEqual(adapter.call_tool("palworld_status", {})["method"], "status")
        bridge.manifest["capabilities"]["status"]["verified"] = False
        with self.assertRaises(server.BridgeError):
            adapter.call_tool("palworld_status", {})
        self.assertEqual([method for method, _ in bridge.calls], ["capabilities", "status", "capabilities"])

    def test_build_preview_requires_real_player_and_one_supported_placement(self):
        bridge = FakeBridge({"build.preview": capability()})
        adapter = server.Adapter(bridge)
        args = {"guild_id": str(uuid.uuid4()), "base_id": str(uuid.uuid4()),
                "player_uid": str(uuid.uuid4()), "structures": [{"build_id": "ItemChest",
                    "support_model_id": str(uuid.uuid4()), "position": {"x": 1, "y": -2, "z": 3},
                    "rotation": {"pitch": 0, "yaw": 90, "roll": 0}}]}
        self.assertEqual(adapter.call_tool("palworld_build_preview", args)["method"], "build.preview")
        invalid = []
        for field in ("guild_id", "base_id", "player_uid"):
            candidate = copy.deepcopy(args)
            del candidate[field]
            invalid.append(candidate)
        candidate = copy.deepcopy(args)
        del candidate["structures"][0]["support_model_id"]
        invalid.append(candidate)
        candidate = copy.deepcopy(args)
        candidate["structures"].append(copy.deepcopy(candidate["structures"][0]))
        invalid.append(candidate)
        for axis in ("pitch", "roll"):
            candidate = copy.deepcopy(args)
            candidate["structures"][0]["rotation"][axis] = 1
            invalid.append(candidate)
        for candidate in invalid:
            with self.assertRaises(server.BridgeError) as caught:
                adapter.call_tool("palworld_build_preview", candidate)
            self.assertEqual(caught.exception.code, "invalid_arguments")
        self.assertEqual(sum(method == "build.preview" for method, _ in bridge.calls), 1)

    def test_checked_in_tool_schemas_match_adapter(self):
        schemas = json.loads(Path(__file__).with_name("tool-schemas.json").read_text())
        self.assertEqual(schemas, {tool.method: tool.schema for tool in server.TOOLS})

    def test_stdio_clean_json_lines_and_invalid_message_recovery(self):
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "future-version", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "unknown"}},
        ]
        stream = io.BytesIO(("not json\n" + "\n".join(json.dumps(m) for m in messages) + "\n").encode())
        output = io.BytesIO()
        server.McpServer(server.Adapter(FakeBridge())).serve(stream, output)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(len(replies), 4)
        self.assertEqual(replies[0]["error"]["code"], -32700)
        self.assertEqual(replies[1]["result"]["protocolVersion"], server.PROTOCOL_VERSIONS[0])
        self.assertEqual(replies[2]["result"]["tools"][0]["name"], "palworld_capabilities")
        self.assertTrue(replies[3]["result"]["isError"])


class AcceptanceStatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "acceptance-status.json"
        self.valid = json.loads(Path(server.__file__).with_name("acceptance-status.json").read_text())
        self.valid["generated_utc"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        self.path.write_text(json.dumps(self.valid))

    def test_local_status_does_not_call_bridge_even_when_disconnected(self):
        class Disconnected:
            def call(self, *args):
                raise AssertionError("Local tool must not invoke transport")
        result = server.Adapter(Disconnected(), self.path).call_tool("palworld_acceptance_status", {})
        self.assertFalse(result["is_live"])
        self.assertFalse(result["current_live_availability_checked"])
        self.assertEqual(result["source"], "local_evidence_snapshot")
        self.assertEqual(len(result["snapshot_sha256"]), 64)
        self.assertIn("NOT LIVE", result["notice"])
        self.assertGreaterEqual(result["snapshot_age_seconds"], 0)
        flags = {f["id"]: f["recorded_public_write_enabled"] for f in result["features"]}
        self.assertEqual(flags, {"storage": True, "workers": False, "build": False})

    def test_missing_invalid_oversized_or_live_claims_fail_closed(self):
        cases = [None, b"not JSON", b" " * (server.MAX_ACCEPTANCE_BYTES + 1)]
        for field, value in [("is_live", True), ("current_live_availability_checked", True),
                             ("source", "runtime_read_only"), ("generated_utc", "2099-01-01T00:00:00Z")]:
            data = copy.deepcopy(self.valid); data[field] = value
            cases.append(json.dumps(data).encode())
        data = copy.deepcopy(self.valid); data["features"][1]["recorded_public_write_enabled"] = True
        cases.append(json.dumps(data).encode())
        data = copy.deepcopy(self.valid); data["features"][0]["evidence_ids"] = ["missing"]
        cases.append(json.dumps(data).encode())
        for body in cases:
            if self.path.exists(): self.path.unlink()
            if body is not None: self.path.write_bytes(body)
            bridge = FakeBridge()
            with self.assertRaises(server.BridgeError) as caught:
                server.Adapter(bridge, self.path).call_tool("palworld_acceptance_status", {})
            self.assertIn(caught.exception.code, {"local_evidence_unavailable", "invalid_local_evidence"})
            self.assertEqual(bridge.calls, [])

    def test_local_artifact_cannot_enable_backend_build_or_worker_writes(self):
        bridge = FakeBridge()
        adapter = server.Adapter(bridge, self.path)
        adapter.call_tool("palworld_acceptance_status", {})
        names = {t["name"] for t in adapter.list_tools()}
        self.assertEqual(names, {"palworld_capabilities", "palworld_acceptance_status"})
        cap = adapter.call_tool("palworld_capabilities", {})
        self.assertEqual(cap["available_methods"], [])
        self.assertEqual(cap["local_diagnostic_methods"], ["acceptance.status"])
        self.assertIn("workers.assign", cap["unavailable_methods"])
        self.assertIn("build.apply", cap["unavailable_methods"])
        for name in ["palworld_workers_assign", "palworld_build_apply"]:
            with self.assertRaises(server.BridgeError):
                adapter.call_tool(name, {"plan_id": "p", "expected_revision": "r", "idempotency_key": str(uuid.uuid4())})
        self.assertTrue(all(m == "capabilities" for m, _ in bridge.calls))

    def test_no_user_path_and_no_local_method_over_ssh(self):
        bridge = FakeBridge()
        with self.assertRaises(server.BridgeError):
            server.Adapter(bridge, self.path).call_tool("palworld_acceptance_status", {"path": "secret"})
        self.assertEqual(bridge.calls, [])
        def runner(*args, **kwargs): raise AssertionError("must not start SSH")
        with self.assertRaises(server.BridgeError):
            server.SshBridge(runner=runner).call("acceptance.status", {})

    def test_stdio_local_tool_call_preserves_clean_json_and_read_only_annotation(self):
        bridge = FakeBridge()
        instance = server.McpServer(server.Adapter(bridge, self.path))
        instance.initialized = instance.ready = True
        out = instance.handle({"jsonrpc": "2.0", "id": 9, "method": "tools/call",
                               "params": {"name": "palworld_acceptance_status", "arguments": {}}})
        self.assertFalse(out["result"]["isError"])
        payload = json.loads(out["result"]["content"][0]["text"])
        self.assertFalse(payload["is_live"])
        tool = server.BY_NAME["palworld_acceptance_status"].descriptor()
        self.assertTrue(tool["annotations"]["readOnlyHint"])
        self.assertFalse(tool["annotations"]["destructiveHint"])
        self.assertEqual(bridge.calls, [])


class TransportTests(unittest.TestCase):
    def test_json_stdin_and_no_user_shell_interpolation(self):
        seen = {}

        def runner(command, **kwargs):
            seen.update(command=command, kwargs=kwargs)
            request = json.loads(kwargs["input"])
            return subprocess.CompletedProcess(command, 0, json.dumps({
                "protocol_version": 1, "request_id": request["request_id"], "ok": True,
                "result": {"alive": True}}).encode(), b"")

        bridge = server.SshBridge(script=r"D:\PalworldServer-LAN\BridgeLab\Invoke-Bridge.ps1", runner=runner)
        self.assertEqual(bridge.call("status", {}), {"alive": True})
        request = json.loads(seen["kwargs"]["input"])
        self.assertEqual(request["method"], "status")
        self.assertTrue(request["deadline_utc"].endswith("Z"))
        self.assertNotIn("status", " ".join(seen["command"]))
        self.assertNotIn("shell", seen["kwargs"])
        self.assertIn("BatchMode=yes", seen["command"])

    def test_reject_shell_injection_in_startup_config_and_arguments(self):
        for host in ("-oProxyCommand=evil", "5090;evil", "5090\nevil"):
            with self.assertRaises(ValueError):
                server.SshBridge(host=host)
        for script in ("relative.ps1", r"D:\bad';evil.ps1", r"D:\$(evil).ps1"):
            with self.assertRaises(ValueError):
                server.SshBridge(script=script)
        with self.assertRaises(server.BridgeError):
            server.validate({"guild_id": "$(evil)"}, server.BY_METHOD["bases.list"].schema)
        with self.assertRaises(server.BridgeError):
            server.validate({"command": "evil"}, server.BY_METHOD["status"].schema)

    def test_timeout_write_has_unknown_outcome_and_no_automatic_retry(self):
        calls = []

        def runner(command, **kwargs):
            calls.append(command)
            raise subprocess.TimeoutExpired(command, kwargs["timeout"])

        bridge = server.SshBridge(timeout=0.05, runner=runner)
        with self.assertRaises(server.BridgeError) as caught:
            bridge.call("storage.apply", {"plan_id": "p1", "expected_revision": "r1",
                "idempotency_key": str(uuid.uuid4())})
        error = caught.exception.as_dict()
        self.assertEqual(error["code"], "timeout")
        self.assertTrue(error["outcome_unknown"])
        self.assertIsNotNone(uuid.UUID(error["request_id"]))
        self.assertEqual(len(calls), 1)

    def test_timeout_read_does_not_claim_unknown_mutation(self):
        def runner(command, **kwargs):
            raise subprocess.TimeoutExpired(command, kwargs["timeout"])

        with self.assertRaises(server.BridgeError) as caught:
            server.SshBridge(timeout=0.05, runner=runner).call("status", {})
        self.assertNotIn("outcome_unknown", caught.exception.as_dict())

    def test_mismatched_or_non_json_response_rejected(self):
        for response in (b"not-json", b'{"protocol_version":1,"request_id":"wrong","ok":true,"result":{}}'):
            def runner(command, response=response, **kwargs):
                return subprocess.CompletedProcess(command, 0, response, b"")
            with self.assertRaises(server.BridgeError) as caught:
                server.SshBridge(runner=runner).call("status", {})
            self.assertEqual(caught.exception.code, "invalid_response")

    def test_ssh_error_does_not_leak_stderr(self):
        def runner(command, **kwargs):
            return subprocess.CompletedProcess(command, 255, b"", b"secret-password=do-not-show")

        with self.assertRaises(server.BridgeError) as caught:
            server.SshBridge(runner=runner).call("status", {})
        self.assertNotIn("secret", json.dumps(caught.exception.as_dict()))


if __name__ == "__main__":
    unittest.main()
