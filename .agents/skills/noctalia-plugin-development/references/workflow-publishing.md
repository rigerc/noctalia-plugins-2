# Development, verification, and distribution

## Local development

Use a drop-in plugin directory such as `$XDG_DATA_HOME/noctalia/plugins/<plugin-name>/`, or point Noctalia at a source repository with a `path` source. Example source repo root has `catalog.toml` plus a directory per plugin name; a single plugin directory itself has `plugin.toml` and `.luau` files. Source precedence: local data dir > user sources > builtin official/community; among user sources, later-added wins.

```sh
# From the installed skill directory:
python3 scripts/scaffold.py --id me/hello --kind starter --output "$HOME/dev/hello"
python3 scripts/validate_plugin.py "$HOME/dev/hello"

# Host native offline linter (only on builds exposing this CLI):
noctalia plugins lint "$HOME/dev/hello"

# Running Noctalia, live plugin manager:
noctalia msg plugins list
noctalia msg plugins source add my-dev path "$HOME/dev/my-plugin-repo"
noctalia msg plugins enable me/hello

# Test IPC:
noctalia msg plugin me/hello:status focused refresh
noctalia msg plugin me/hello:service all refresh
noctalia msg panel-toggle me/hello:panel
```

The exact entry IDs here are **examples**; use IDs declared in the plugin's `plugin.toml`. `focused` targets a focused-output widget placement; `all` matches singleton entries and every instance of a surface entry. Plugins need to be enabled and widgets need to be placed on a bar to respond as visible widgets. Changes to `.luau` generally hot-reload. Manifest changes are picked up on configuration reload. Verify which source copy won when a plugin ID exists in multiple sources.

## Verification matrix

| Test | Static validator | Native offline lint | Running shell |
| --- | :---: | :---: | :---: |
| TOML parsing, required fields, versions, entry file path, English translations | ✓ | partial | ✓ |
| Minimum API gates known from snapshot | ✓ (heuristic) | not guaranteed | ✓ |
| Literal `getConfig("key")` setting key references | ✓ (entry scripts) | ✓ (entries + modules) | warnings |
| Luau parse/type analysis | — | not a full compiler | runtime or luau-analyze |
| Per-output bar size/orientation, panel keyboard focus, UI rendering | — | — | ✓ |
| IPC, state watchers, hot reload, async stale responses | — | — | ✓ |
| Compositor-dependent layer, idle, keyboard, pointer behavior | — | — | ✓ |

`python3 scripts/validate_plugin.py` is provided by this skill and depends on **Python 3.11+** (`tomllib`). It does not compile Luau. Run `noctalia plugins lint` for richer host-native setting matching if supported. Inspect output and `noctalia` process logs; unknown UI props and missing settings keys are logged by the host. Test all active entry kinds with a running Noctalia instance and, ideally, a secondary output.

## Publishing a source repository

Repository layout:

```
my-plugins/
  catalog.toml
  hello/
    plugin.toml
    widget.luau
    README.md
    thumbnail.webp
    translations/en.json
```

The directory name matches the suffix of the plugin ID (`me/hello` → `hello/`). The catalog needs an array of `[[plugin]]` with `id`, `name`, and positive integer `plugin_api` (other metadata recommended). The source docs show `description`, `version`, `author`, `license`, `icon`, `tags`, `dependencies`. Example:

```toml
[[plugin]]
id = "me/hello"
name = "Hello"
version = "1.0.0"
plugin_api = 3
author = "me"
license = "MIT"
description = "Sample plugin."
```

For a compatibility bump, publishing a new high-level version can make the plugin unavailable on older Noctalia versions. Optionally include `[[plugin.release]]` rows with lower `plugin_api`, older version, and **full 40-character Git commit** `rev` to provide earlier compatible versions. This only works for `git` sources; the publisher should generate release rows from actual Git history instead of fabricating commit IDs. In CI fetch full history.

External installation of a repo:

```sh
noctalia msg plugins source add my-repo git https://example.com/my-plugins.git
```

Third-party submissions go to `noctalia-dev/community-plugins`, not `official-plugins`. Community submissions require `plugin.toml`, scripts, `README.md`, `thumbnail.webp`, and `translations/en.json`; run the community repository's own validator/CI before a PR. A plugin's `dependencies` metadata announces external tools but does **not** prevent enabling if dependencies are absent; detect availability in code and explain requirements in README.

## Security and distribution review

Plugins execute as **trusted code**. No capability broker, filesystem sandbox, or consent gate exists for plugin process/file functions. Review any external binary invocation and URLs before running third-party plugins. Publish a clear network/dependency/data handling statement, license, limitations, and user-visible setup steps. Never claim secret storage or isolation beyond what the host actually implements.

## References and trust order

1. User's checked-out Noctalia source matching installed binary.
2. This skill's offline snapshot under `references/source-docs/` and `references/plugin-api.json`.
3. Current official docs: https://docs.noctalia.dev/noctalia/plugins/development/
4. Official plugin examples: https://github.com/noctalia-dev/official-plugins
5. Community publishing repository: https://github.com/noctalia-dev/community-plugins

If the source at #1 differs from this skill's snapshot, source at #1 wins. Never silently assume current docs describe the installed plugin host exactly.
