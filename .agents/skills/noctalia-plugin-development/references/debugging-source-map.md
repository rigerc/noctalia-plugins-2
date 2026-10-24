# Deep debugging: where the native Noctalia host implements plugin behavior

These are file paths **inside the user-provided Noctalia C++ source archive**, not files required for an individual plugin package. Use them when docs and live behavior disagree, when debugging host bugs, or when writing a plugin against a customized host build.

| Symptom / question | Inspect in Noctalia host source | Diagnostics |
| --- | --- | --- |
| Manifest rejected; duplicate ids, unknown entry settings, API minimums | `src/scripting/plugin_manifest.cpp`, `plugin_id.h`, `plugin_api.h` | Compare error text with parser branches, check TOML scoping |
| `getConfig()` returns nil or wrong scope | `src/scripting/plugin_bindings.cpp`, `plugin_lint.cpp`, `plugin_manager.cpp` | Read manifest scopes and run `noctalia plugins lint` |
| Entry does not load or reload; modules not watched | `src/scripting/plugin_manager.cpp`, `plugin_script_watcher.cpp`, `plugin_file_cache.cpp`, `plugin_registry.cpp` | Check source precedence, reload trigger, VM context |
| Service startup, enable, shutdown, IPC | `src/scripting/plugin_service_host.cpp`, `plugin_ipc.cpp`, `plugin_runtime_context.h` | Check explicit enable vs ordinary startup, output target |
| Bar widget missing, wrong dimensions, click/scroll overridden | `src/shell/bar/widgets/plugin_widget.cpp` | Check placement on bar, orientation, `actions` bindings |
| Panel clipping, keyboard focus, outside-click, wrong placement | `src/shell/panel/plugin_panel.cpp`, `src/scripting/plugin_panel_shell.cpp` | Compare manifest width/height/placement/focus options |
| Layer not visible, wrong output, focus stealing | `src/shell/plugin_layer/plugin_layer.cpp`, `plugin_layer_host.cpp`, `src/scripting/plugin_layer_config.cpp` | Check lazy show, per-output instances, anchors and layer |
| Launcher does not display results or current query | `src/launcher/plugin_launcher_provider.cpp` | Ensure `setResults` echoes each original query; debounce |
| Control-center tile or desktop widget missing | `src/shell/control_center/plugin_shortcut.cpp`, `src/shell/desktop/widgets/plugin_desktop_widget.cpp` | Confirm entry enabled, location registered, surfaces present |
| Plugin data or Git source precedence incorrect | `src/scripting/plugin_source_paths.cpp`, `plugin_catalog.cpp`, `plugin_git.cpp`, `plugin_state_store.cpp` | Inspect resolved runtime/source/data directory |
| Unexpected plugin API feature behavior | `src/scripting/plugin_api.h`, `docs/plugin-api.json` | Cross-check actual compiled `kCurrentPluginApiVersion` |

## Repro procedure

1. Reproduce with the smallest manifest and entry `.luau` script. Record host version, `plugin_api`, entry kind, compositor, and relevant output.
2. Run `python3 scripts/validate_plugin.py PLUGIN_DIR` (for basic issues) and, if available, `noctalia plugins lint PLUGIN_DIR` (for literal/loaded module `getConfig` mistakes).
3. Verify plugin-source precedence. Only one canonical `author/plugin` copy wins; a local data-dir copy overrides installed sources. Confirm the file under test is the loaded file.
4. Enable plugin and place widget/desktop entry in the host UI if applicable. Dispatch `noctalia msg plugin author/plugin:entry all test-event` to prove `onIpc` is wired. Use a focused/output target for output-scoped instances.
5. Observe logs: `noctalia.log` includes plugin context; missing declared settings and unsupported UI props should surface in host logging.
6. For timing, record entry reload sequence and outstanding async callbacks; guard completions by query or request generation.
7. If behavior still contradicts the docs, inspect exact host source files above and distinguish **host bug**, **API mismatch**, and **plugin misuse**. Report concrete reproduction and expected/actual behavior.

## Design review beyond correctness

- Multiple outputs: `barWidget.outputName` vs `noctalia.focusedOutputName` are different; design per-instance vs global state accordingly.
- Isolation: a service and panel never share Luau globals. A `require` cache is also per-entry and can be hot-reloaded independently.
- Resource cleanup: streams owned by entry runtime terminate on reload; detached commands can outlive the runtime. `onExit` does not run on crashes/SIGKILL.
- Privacy: settings are not a cryptographic secret store; native plugins can run system commands, read files and call HTTP. Treat all third-party plugin code as trusted execution.
- Compatibility: a feature defined in the source's API 42 table may be unreleased in a packaged host. Verify actual compiled `plugin_api` constants and do not mislabel API adoption as backward-compatible.
