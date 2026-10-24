"""Offline contract tests: Python stdlib only, no Noctalia session required."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCAFFOLD = ROOT / "scripts/scaffold.py"
VALIDATE = ROOT / "scripts/validate_plugin.py"
KINDS = ("starter", "widget", "panel", "service", "shortcut", "launcher_provider", "desktop_widget", "layer")


def run(*args: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, *map(str, args)], text=True, capture_output=True, check=False)


class SkillTests(unittest.TestCase):
    def test_all_scaffolds_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for kind in KINDS:
                with self.subTest(kind=kind):
                    directory = Path(tmp) / kind
                    generated = run(SCAFFOLD, "--id", f"acme/{kind}", "--kind", kind, "--output", directory)
                    self.assertEqual(generated.returncode, 0, generated.stderr)
                    validated = run(VALIDATE, directory)
                    self.assertEqual(validated.returncode, 0, validated.stdout + validated.stderr)
                    self.assertTrue((directory / "translations/en.json").is_file())

    def test_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo"
            self.assertEqual(run(SCAFFOLD, "--id", "me/demo", "--output", path).returncode, 0)
            again = run(SCAFFOLD, "--id", "me/demo", "--output", path)
            self.assertNotEqual(again.returncode, 0)
            self.assertIn("refusing to overwrite", again.stderr)

    def test_bad_version_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo"
            run(SCAFFOLD, "--id", "me/demo", "--output", path)
            manifest = path / "plugin.toml"
            manifest.write_text(manifest.read_text().replace('version = "0.1.0"', 'version = "1.0.0-beta"'))
            result = run(VALIDATE, path)
            self.assertEqual(result.returncode, 1)
            self.assertIn("version must be exactly", result.stdout)

    def test_unknown_setting_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo"
            run(SCAFFOLD, "--id", "me/demo", "--output", path)
            source = path / "widget.luau"
            source.write_text(source.read_text() + '\nlocal v = noctalia.getConfig("unlisted_setting")\n')
            result = run(VALIDATE, path)
            self.assertEqual(result.returncode, 1)
            self.assertIn("undeclared getConfig", result.stdout)

    def test_feature_level_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo"
            run(SCAFFOLD, "--id", "me/demo", "--kind", "panel", "--output", path)
            source = path / "panel.luau"
            source.write_text(source.read_text() + '\nnoctalia.getColor("primary")\n')
            result = run(VALIDATE, path)
            self.assertEqual(result.returncode, 1)
            self.assertIn("minimum recognizable level 31", result.stdout)

    def test_content_height_requires_limit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo"
            run(SCAFFOLD, "--id", "me/demo", "--kind", "panel", "--output", path)
            manifest = path / "plugin.toml"
            manifest.write_text(manifest.read_text().replace('height = 230', 'height = "content"').replace('plugin_api = 3', 'plugin_api = 42'))
            result = run(VALIDATE, path)
            self.assertEqual(result.returncode, 1)
            self.assertIn("requires positive integer max_height", result.stdout)

    def test_layer_requires_api36(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo"
            run(SCAFFOLD, "--id", "me/demo", "--kind", "layer", "--output", path)
            manifest = path / "plugin.toml"
            manifest.write_text(manifest.read_text().replace('plugin_api = 36', 'plugin_api = 3'))
            result = run(VALIDATE, path)
            self.assertEqual(result.returncode, 1)
            self.assertIn("minimum recognizable level 36", result.stdout)

    def test_missing_translation_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo"
            run(SCAFFOLD, "--id", "me/demo", "--output", path)
            (path / "translations/en.json").unlink()
            result = run(VALIDATE, path)
            self.assertEqual(result.returncode, 1)
            self.assertIn("translation label_key", result.stdout)


if __name__ == "__main__":
    unittest.main()
