"""Integration-contract smoke tests for T3 Monitor (no T3 installation required)."""
from __future__ import annotations

import json
import re
import sqlite3
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "t3"
SERVICE = (PLUGIN / "service.luau").read_text(encoding="utf-8")


def extract_sql(name: str) -> str:
    match = re.search(rf"local {name} = \[\[(.*?)\]\]", SERVICE, re.DOTALL)
    if match is None:
        raise AssertionError(f"{name} SQL declaration missing")
    return match.group(1)


def fixture_database() -> sqlite3.Connection:
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    db.executescript(
        """
        CREATE TABLE projection_projects (
          project_id TEXT, title TEXT, workspace_root TEXT, deleted_at TEXT
        );
        CREATE TABLE orchestration_v2_projection_threads (
          thread_id TEXT, title TEXT, project_id TEXT, deleted_at TEXT
        );
        CREATE TABLE orchestration_v2_projection_subagents (
          subagent_id TEXT, thread_id TEXT, child_thread_id TEXT,
          status TEXT, started_at TEXT, completed_at TEXT,
          updated_at TEXT, payload_json TEXT
        );
        CREATE TABLE orchestration_v2_projection_runtime_requests (
          thread_id TEXT, status TEXT
        );
        INSERT INTO projection_projects VALUES ('p1','Alpha','/home/a',NULL);
        INSERT INTO projection_projects VALUES ('gone','Old','/home/old','2026-01-01');
        INSERT INTO orchestration_v2_projection_threads
          VALUES ('parent','Parent task','p1',NULL);
        INSERT INTO orchestration_v2_projection_subagents VALUES
          ('child1','parent','childthread','running','2026-10-24T10:00:00Z',
           NULL,'2026-10-24T10:01:00Z',
           '{"title":"Research API","driver":"codex","model":"gpt","progress":"Inspecting"}');
        INSERT INTO orchestration_v2_projection_runtime_requests VALUES ('childthread','pending');
        INSERT INTO orchestration_v2_projection_runtime_requests VALUES ('other','resolved');
        """
    )
    return db


class MonitorContractTests(unittest.TestCase):
    def test_manifest_is_native_and_read_only(self) -> None:
        manifest = tomllib.loads((PLUGIN / "plugin.toml").read_text(encoding="utf-8"))
        self.assertEqual(manifest["id"], "rigerc/t3")
        self.assertEqual(manifest["plugin_api"], 24)
        self.assertEqual([p["id"] for p in manifest["service"]], ["monitor"])
        self.assertEqual([p["id"] for p in manifest["widget"]], ["status"])
        self.assertEqual([p["id"] for p in manifest["panel"]], ["dashboard"])
        self.assertIn("excluded_projects", [s["key"] for s in manifest["setting"]])
        self.assertNotIn("t3 thread send", SERVICE)
        self.assertNotIn("t3 thread start", SERVICE)

    def test_sqlite_queries_match_v2_fixture(self) -> None:
        with fixture_database() as db:
            projects = db.execute(extract_sql("PROJECT_SQL")).fetchall()
            self.assertEqual([row["project_id"] for row in projects], ["p1"])
            children = db.execute(extract_sql("CHILD_SQL")).fetchall()
            self.assertEqual(len(children), 1)
            self.assertEqual(children[0]["parent_id"], "parent")
            self.assertEqual(children[0]["project_id"], "p1")
            self.assertEqual(json.loads(children[0]["payload_json"])["progress"], "Inspecting")
            pending = db.execute(extract_sql("REQUEST_SQL")).fetchall()
            self.assertEqual([(row["thread_id"], row["pending_count"]) for row in pending],
                             [("childthread", 1)])

    def test_implementation_uses_safe_subprocess_argv(self) -> None:
        self.assertIn('"\u002dreadonly"', SERVICE)
        self.assertIn('"\u002djson"', SERVICE)
        self.assertIn('noctalia.runAsync(argv,', SERVICE)
        self.assertIn('"thread", "list",', SERVICE)
        self.assertIn('"thread", "show",', SERVICE)
        self.assertNotIn("os.execute(", SERVICE)
        self.assertIn('status == "completed"', SERVICE)

    def test_translations_parse(self) -> None:
        data = json.loads((PLUGIN / "translations/en.json").read_text(encoding="utf-8"))
        self.assertIn("excluded_projects", data["settings"])


if __name__ == "__main__":
    unittest.main()
