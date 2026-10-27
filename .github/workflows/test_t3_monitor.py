"""Integration-contract smoke tests for T3 Monitor (no T3 installation required).

The bridge is replayed against recorded WebSocket frames, and the same bridge
output is replayed through the Luau reducer, so the transport and the state
machine are both covered without a running T3 Code.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "t3"
SERVICE = (PLUGIN / "service.luau").read_text(encoding="utf-8")
BRIDGE = (PLUGIN / "bridge.mjs").read_text(encoding="utf-8")
FIXTURES = PLUGIN / "fixtures"


def node_binary() -> str | None:
    return shutil.which("node")


def lua_binary() -> str | None:
    return shutil.which("lua5.4") or shutil.which("lua")


def run_bridge(fixture: str) -> subprocess.CompletedProcess[str]:
    node = node_binary()
    if node is None:
        raise unittest.SkipTest("node is not installed")
    return subprocess.run(
        [node, str(PLUGIN / "bridge.mjs"), "--replay", str(FIXTURES / fixture)],
        capture_output=True,
        text=True,
        timeout=60,
    )


def parse_ndjson(text: str) -> list[dict]:
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def lua_literal(value) -> str:
    """Serialize JSON data as a Lua table literal."""
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{escaped}"'
    if isinstance(value, list):
        return "{" + ", ".join(lua_literal(item) for item in value) + "}"
    if isinstance(value, dict):
        pairs = ", ".join(
            f"[{lua_literal(key)}] = {lua_literal(item)}" for key, item in value.items()
        )
        return "{" + pairs + "}"
    raise TypeError(f"cannot serialize {type(value)!r}")


class MonitorContractTests(unittest.TestCase):
    def test_manifest_is_native_and_read_only(self) -> None:
        manifest = tomllib.loads((PLUGIN / "plugin.toml").read_text(encoding="utf-8"))
        self.assertEqual(manifest["id"], "rigerc/t3")
        self.assertEqual(manifest["plugin_api"], 24)
        self.assertEqual([p["id"] for p in manifest["service"]], ["monitor"])
        self.assertEqual([p["id"] for p in manifest["widget"]], ["status"])
        self.assertEqual([p["id"] for p in manifest["panel"]], ["dashboard"])
        keys = [s["key"] for s in manifest["setting"]]
        self.assertIn("excluded_projects", keys)
        self.assertIn("node_executable", keys)
        self.assertIn("token_file", keys)
        for removed in ("sqlite_path", "sqlite_executable", "t3_executable"):
            self.assertNotIn(removed, keys, f"{removed} is no longer used")

    def test_service_uses_the_bridge_not_sqlite_or_the_cli(self) -> None:
        self.assertIn("noctalia.runStream(", SERVICE)
        self.assertIn('require("./reducer.luau")', SERVICE)
        for forbidden in (
            "sqlite3",
            "runAsync",
            "thread list",
            "thread show",
            "PROJECT_SQL",
        ):
            self.assertNotIn(forbidden, SERVICE)
        # Read-only: the plugin never sends prompts or approves requests.
        self.assertNotIn("t3 thread send", SERVICE)
        self.assertNotIn("t3 thread start", SERVICE)
        self.assertNotIn(
            "noctalia.notify(", (PLUGIN / "widget.luau").read_text(encoding="utf-8")
        )

    def test_bridge_is_dependency_free_and_checks_node(self) -> None:
        imports = re.findall(r'from "([^"]+)"', BRIDGE)
        self.assertTrue(imports)
        for module in imports:
            self.assertTrue(module.startswith("node:"), f"unexpected import {module}")
        self.assertIn("orchestration.subscribeShell", BRIDGE)
        self.assertIn("orchestrationProtocol", BRIDGE)
        self.assertIn("websocket-ticket", BRIDGE)
        self.assertIn("Node 22 or newer is required", BRIDGE)

    def test_bridge_replay_matches_the_recorded_events(self) -> None:
        result = run_bridge("ws-shell.ndjson")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = parse_ndjson(
            (FIXTURES / "events.ndjson").read_text(encoding="utf-8")
        )
        self.assertEqual(parse_ndjson(result.stdout), expected)
        self.assertEqual(expected[0]["type"], "snapshot")
        self.assertEqual(expected[0]["scope"], "full")
        self.assertEqual(expected[1]["scope"], "projects")
        kinds = [event["type"] for event in expected]
        self.assertEqual(kinds.count("thread.updated"), 4)
        self.assertIn("thread.removed", kinds)

    def test_bridge_reports_a_protocol_defect(self) -> None:
        result = run_bridge("ws-defect.ndjson")
        self.assertEqual(result.returncode, 1)
        events = parse_ndjson(result.stdout)
        self.assertEqual(events[-1]["type"], "health")
        self.assertEqual(events[-1]["state"], "offline")
        self.assertEqual(events[-1]["reason"], "protocol")

    def test_reducer_replays_the_bridge_output(self) -> None:
        lua = lua_binary()
        if lua is None:
            self.skipTest("lua5.4 is not installed")
        events = parse_ndjson((FIXTURES / "events.ndjson").read_text(encoding="utf-8"))
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as handle:
            handle.write("return " + lua_literal(events) + "\n")
            fixture_path = handle.name
        result = subprocess.run(
            [
                lua,
                str(ROOT / ".github" / "workflows" / "t3_reducer_test.lua"),
                fixture_path,
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 failure(s)", result.stdout)

    def test_translations_parse(self) -> None:
        data = json.loads(
            (PLUGIN / "translations" / "en.json").read_text(encoding="utf-8")
        )
        manifest = tomllib.loads((PLUGIN / "plugin.toml").read_text(encoding="utf-8"))

        def resolve(dotted: str) -> str | None:
            node = data
            for part in dotted.split("."):
                if not isinstance(node, dict) or part not in node:
                    return None
                node = node[part]
            return node if isinstance(node, str) else None

        for setting in manifest["setting"]:
            self.assertIsNotNone(resolve(setting["label_key"]), setting["label_key"])
            if "description_key" in setting:
                self.assertIsNotNone(
                    resolve(setting["description_key"]), setting["description_key"]
                )
        self.assertIsNotNone(resolve("token.hint"))
        self.assertIsNotNone(resolve("token.copy"))
        self.assertIsNotNone(resolve("token.requirements"))


if __name__ == "__main__":
    unittest.main()
