---
name: noctalia-plugin-development
description: >-
  Develop, maintain, debug, test, and publish Noctalia v5+ native Wayland shell
  plugins using plugin.toml manifests and isolated Luau entry scripts. Use for
  plugin widgets, panels, services, launcher providers, control-center shortcuts,
  desktop widgets, layer surfaces, declarative ui.* trees, scripting APIs,
  cross-entry state, IPC, plugin API compatibility, or Noctalia plugin reviews.
  Distinguish native Luau plugins from older QML/Quickshell extensions.
---

# Noctalia Plugin Development — Advanced Skill

## Source and compatibility contract

This skill is derived from the **user-provided Noctalia source snapshot** (`noctalia-src.zip`), whose docs identify native Noctalia v5 plugins and plugin API **levels 3–42**. The snapshot's levels 35–42 have no released Noctalia version mapped; **do not assume they ship in a stable build**. Consult the target installation, its source, and `references/plugin-api.json` before selecting features. The included `references/source-docs/` is an **offline copy of the snapshot's plugin development docs**, not a guarantee that the installed host matches them.

**Critical distinction:** This is a **native Wayland/OpenGL ES Noctalia v5+ plugin skill**. Plugin code is Luau (`*.luau`) with `plugin.toml`; **do not generate Quickshell/QML, `manifest.json`, `main.qml`, or JavaScript UI components** for this target. If user code is clearly targeting legacy Noctalia, confirm its installed version or explicitly describe a migration.

## Workflow — execute in this order

1. **Inspect target project and host.** Read any existing `plugin.toml` and the relevant `.luau` files; inspect the user's pinned Noctalia source/version or installed `noctalia` binary. Determine whether this is a new plugin, a modification, a review, or a migration. Never silently replace an existing layout.
2. **Choose minimal entry kinds.** `widget` for bars; `shortcut` for control-center tiles; `launcher_provider` for launcher query results; `desktop_widget` for tiles on the desktop; `panel` for pop-up UI; `layer` for plugin-owned Wayland layer surfaces (API ≥36); `service` for headless work. A plugin can combine entry kinds; an entry gets its own isolated VM.
3. **Define the manifest first.** Required root fields: `id`, `name`, `version`, `plugin_api`; entry tables such as `[[widget]]` include `id` and `entry`. Store static settings schemas in the manifest, not code. IDs use the `author/plugin:entry` addressing model; `plugin_api` is the **oldest level needed**, not the latest level known.
4. **Implement small Luau entry scripts.** Top level initializes the entry and registers watchers. Export only host-recognized global lifecycle functions (`update`, `onClick`, `onOpen`, `onIpc`, etc.) appropriate to the entry kind. Use `noctalia.*` and surface APIs from the docs; do not invent APIs.
5. **Make runtime responsibilities explicit.** Use `noctalia.state` for ephemeral cross-entry plain-data communication, `noctalia.pluginDataDir()` for persistence, and async HTTP/process/file interfaces when operations can block. Handle error states, cleanup, and reloads.
6. **Use native UI conventions.** For simple bar widgets use imperative `barWidget.setText`/`setGlyph`; for composite bars use `barWidget.render(ui.*)`; panels, desktop widgets, and layers render `ui.*` trees. Prefer semantic palette roles, stable keys in repeated nodes, and accessible state indicators.
7. **Establish feature gates.** Calculate the required minimum `plugin_api` from every manifest option and Lua feature. Consult `references/compatibility.md` and `references/plugin-api.json`. If a host API is unknown, explicitly flag it rather than guessing.
8. **Validate; test on a live compositor if available.** Use `python3 scripts/validate_plugin.py path/to/plugin`; also use **host-native** `noctalia plugins lint path/to/plugin` if the installed build exposes it. Native offline lint checks `getConfig` cross-references and missing files; neither static validator replaces live tests.
9. **Deliver deployable results.** Give complete `plugin.toml`, entry scripts, translation keys/assets where needed, precise setup commands, manual tests, an API compatibility statement, and what could not be tested. For public distribution, follow `references/workflow-publishing.md`.

## Fast navigation / load details only when needed

| Task | Read |
| --- | --- |
| Manifest, settings, entries, callbacks | `references/manifest-entries.md` |
| UI trees, bar/panel/desktop/layer affordances | `references/declarative-ui.md` |
| Runtime and patterns: HTTP, process, state, persistence | `references/runtime-patterns.md` |
| Minimum plugin API level, unreleased features | `references/compatibility.md`, `references/plugin-api.json` |
| Local installs, diagnostics, security, publishing | `references/workflow-publishing.md` |
| Host-internal C++ paths and advanced troubleshooting | `references/debugging-source-map.md` |
| Exhaustive source-specific function/property descriptions | `references/source-docs/{manifest,entries,declarative-ui,runtime-api,workflow,plugin-api,index}.mdx` |
| C++ host internals (if the user's repository includes them) | `src/scripting/{plugin_manifest.cpp,plugin_bindings.cpp,plugin_manager.cpp,plugin_lint.cpp}` and `src/shell/{bar/widgets/plugin_widget.cpp,panel/plugin_panel.cpp}` |

## Working commands

Generate a ready-to-edit starter (Python 3.11+ required for TOML validation):

```sh
python3 scripts/scaffold.py --id acme/example --kind starter --output ./example
# --kind: starter, widget, panel, service, shortcut, launcher_provider, desktop_widget, layer
python3 scripts/validate_plugin.py ./example
# If the installed native Noctalia binary supports it:
noctalia plugins lint ./example
```

When working within this skill directory, use paths above. In a different working directory, adjust script paths to the installed skill location. The scaffold is a **starting point**, not a feature-rich application or substitute for live runtime testing. It never overwrites an existing output directory.

## Non-negotiable implementation rules

- **Entry isolation:** never assume Lua globals/functions can cross entry VMs. Share plain data via `noctalia.state.*`; changes are copied and process-lifetime only. Loaded modules are cached separately per entry, not globally.
- **Settings are declared:** `noctalia.getConfig(key)` only resolves keys from plugin-level `[[setting]]` and applicable entry settings. Use `noctalia.getSetting(path)` only for general shell configuration (API ≥26). Manifest `label_key`/`description_key` must resolve in `translations/en.json`.
- **Callbacks:** UI `onChange` callbacks receive **strings**; convert types intentionally (`value == "true"`, `tonumber(value)`). Named global callback strings work from the baseline; inline closures require API ≥9.
- **Keyboard ownership:** bars cannot host interactive keyboard controls. Panels can; special key capture requires explicit `capture_keys` (API ≥13). `Escape` remains host-owned.
- **UI state:** `ui.input` is *uncontrolled* after initialization, whereas toggle/select/slider are value-driven. Repeated UI nodes need stable `key` values. `ui.image` paths are local files, not URLs.
- **Bar ownership:** do not mix imperative `setText`/`setGlyph` with an active `barWidget.render` tree; choose one presentation model. Widget action bindings can override pointer callbacks; middle-click defaults to opening settings.
- **Security:** plugins are trusted user code, **not filesystem or permission sandboxed**. Never eval untrusted strings or interpolate untrusted input into a shell command. Prefer `noctalia.runAsync({ program, arg1, ... }, callback)` with API ≥24. Do not embed credentials in command-line arguments/logs; use native HTTP headers and avoid `allow_insecure_tls`.
- **Performance:** prefer async I/O and request debouncing; avoid tight update loops or high-frequency file reads. Use `onExit` to clean up external resources, accounting for abrupt shutdown where callbacks cannot run.
- **Persistence:** write under `noctalia.pluginDataDir()`, never the plugin source/runtime copy. Avoid saving secrets in world-readable files; document secrets handling and third-party network traffic.
- **Honest validation:** if a Luau compiler, Noctalia executable, or Wayland session is unavailable, say static checks passed but **runtime behavior was not verified**.

## Completion checklist

- [ ] Manifest parses; identity/version/API valid; one or more unique entry ids with readable `.luau` files.
- [ ] Every referenced declared setting matches a type, default, translation, and usage site.
- [ ] Minimum `plugin_api` covers all used features; unreleased levels are called out.
- [ ] Entry scripts implement supported lifecycle hooks, scoped correctly to each entry type.
- [ ] No unauthorized shell interpolation; errors/async races/reloads handled; no leaked external resources.
- [ ] UI sizing, focus, empty/loading/error states, tooltip/labels, and theme roles tested as applicable.
- [ ] Static validator runs; native lint and IPC/live checks attempted or explicitly marked unavailable.
- [ ] README documents install, configuration, dependencies, examples, and distribution metadata.

## User request interpretation

For a request to **create a plugin**, output runnable project files. For **fix/debug**, inspect actual code and logs, reproduce with minimal steps, repair, and revalidate. For **review**, identify correctness/security/API regressions with file locations and confidence. For **migrate**, inventory old QML assumptions, map to available Luau entry kinds, and flag unsupported capabilities rather than claiming a mechanical one-to-one translation.
