# Noctalia Plugin Development — Advanced AI Skill

An installable, source-grounded skill for authoring native **Noctalia v5+** plugins using `plugin.toml` and isolated **Luau** entry scripts. Built against the user-supplied Noctalia C++ source/docs snapshot, which declares plugin API levels **3–42**. APIs 35–42 are listed as unreleased in that snapshot.

## What is included

- `SKILL.md` — skill activation, architecture, step-by-step design/build/review instructions, non-negotiable rules, and validation checklist.
- `references/` — curated manifest, UI, runtime, compatibility, and publishing references; `source-docs/` holds copied plugin developer docs from the supplied source archive; `plugin-api.json` holds the exact API feature ledger.
- `scripts/scaffold.py` — scaffold generator for all seven entry kinds plus a combined widget + panel + service starter.
- `scripts/validate_plugin.py` — Python 3.11+ preflight checks for manifest/translation/entry errors and recognizable compatibility gates.
- `examples/` — generated sample plugins.
- `tests/` — offline regression tests for valid and invalid manifests.

## Install as an agent skill

Keep this directory intact (the root must contain `SKILL.md`). Copy `noctalia-plugin-development/` to a skill directory supported by your agent. For example:

```sh
# Codex user skill installation, when ~/.agents/skills is your configured discovery directory:
mkdir -p ~/.agents/skills
cp -a noctalia-plugin-development ~/.agents/skills/

# Claude Code's project-scoped skills convention:
mkdir -p .claude/skills
cp -a noctalia-plugin-development .claude/skills/
```

Agent products differ in their discovery paths; consult your agent's documentation if those directories are not used. Alternatively, attach `SKILL.md` and references directly to a coding assistant and ask it to follow the workflow.

## Run standalone tools

```sh
python3 scripts/scaffold.py --id acme/my-plugin --kind starter --output ./my-plugin
python3 scripts/validate_plugin.py ./my-plugin
python3 -m unittest discover -s tests -v

# Optional, on a supported running or installed Noctalia native build:
noctalia plugins lint ./my-plugin
```

**No Luau compilation or live Wayland/Noctalia runtime checks are possible using these scripts alone.** The provided static validator is deliberately heuristic; run the native linter and interactively test the plugin with a compatible host.

## Source and provenance

From the user-provided `noctalia-src.zip`, SHA-256:

`98ae4363fd0923ca2e4d4e54d6ba877483bc3470c5d2a343caa8dab22c333cb9`

Primary source paths in that archive: `docs/user/plugins/development/*.mdx`, `docs/plugin-api.json`, `src/scripting/plugin_api.h`, `src/scripting/plugin_manifest.cpp`, `src/scripting/plugin_id.h`, and `src/scripting/plugin_lint.cpp`. The original package's plugin API table maps levels 35–42 to an unreleased version. This skill does not ship the full original C++ source; it ships the seven relevant source documentation pages and the API JSON feature ledger.

Official docs: https://docs.noctalia.dev/noctalia/plugins/development/

**Third-party tool:** This is an AI agent skill to help write Noctalia plugins. It is **not itself a Noctalia shell plugin** and should not be installed in Noctalia's plugins folder.
