# Runtime API patterns — implementation and failure modes

For exhaustive method/argument/return signatures consult `source-docs/runtime-api.mdx`. The host's `noctalia.*` API is not a browser, QML runtime, or generic Lua POSIX API. Entry VMs are isolated from each other but plugins are trusted code with access to the host's filesystem/process functions.

## Entrypoint lifecycle

```lua
local enabled = true
noctalia.setUpdateInterval(5000) -- update() scheduled in milliseconds; <16ms is clamped

function update()
  -- cheap, bounded, synchronous work only
end

function onIpc(event, payload)
  if event == "refresh" then update() end
end

function onExit(_signal, reason)
  -- cleanup hooks, if possible. reason requires API >=17.
end
```

Top-level code executes when the entry loads. Service `onEnable()` is **not called on routine startup**, only on explicit user enable (API ≥17). Config changes: service `onConfigChanged()` means in-place update; without it services restart; other surface entry types rebuild. Hot reload makes stale async callback/order concerns important.

## Plugin settings vs shell settings

`noctalia.getConfig("interval")`: **manifest-declared** setting, entry-specific overrides apply. `noctalia.getSetting("shell.offline_mode")`: general shell config (API ≥26). `noctalia.getColor("primary")` returns `#RRGGBB` or nil (API ≥31). `noctalia.isDarkMode()` reflects active shell palette mode. `noctalia.outputs()` returns connected outputs with name/geometry/scale/focus; `noctalia.focusedOutputName()` returns focused output.

## Cross-entry state (process lifetime)

```lua
-- service.luau (producer)
local value = 0
noctalia.setUpdateInterval(1000)
function update()
  value = value + 1
  noctalia.state.set("count", value)
end

-- widget.luau (consumer)
local function show(v)
  barWidget.setText(tostring(v or 0))
end
show(noctalia.state.get("count"))
noctalia.state.watch("count", show)
```

`noctalia.state.get/set/watch` accepts **plain copied values** (numbers/strings/bools/plain tables). Do not send VM functions, native handles, UI trees, or assume state survives a shell restart. For config-dependent caches, include source/config identity in cached state and invalidate it when settings change.

## Persistent data (survives restart)

```lua
local dir, err = noctalia.pluginDataDir()
if not dir then
  noctalia.notifyError("Plugin data unavailable", tostring(err))
else
  local path = dir .. "/cache.json"
  local raw = noctalia.readFile(path)
  if raw then
    local value, decodeErr = noctalia.json.decode(raw)
    if value then
      -- restore validated data
    else
      noctalia.log("Invalid cache: " .. tostring(decodeErr))
    end
  end
end
```

Write with `noctalia.writeFile(path, noctalia.json.encode(value))` **only after** checking encode success. `noctalia.pluginDir()` points to a runtime/source directory that may be replaced during updates; don't persist there. `noctalia.readFileAsync(path, cb)` (API ≥23) is limited to **4 MiB** and four outstanding requests per runtime. Relative paths for filesystem helpers resolve under the plugin directory; `~` expands home. Helpers are **not a permission sandbox**.

## Safe external commands (API ≥24)

```lua
local accepted = noctalia.runAsync({ "git", "-C", checkoutDir, "status", "--short" }, function(r)
  if r.timedOut or r.exitCode ~= 0 then
    noctalia.notifyError("Git status failed", r.stderr or "")
    return
  end
  noctalia.log(r.stdout)
end)
if not accepted then noctalia.notifyError("Could not start command") end
```

Prefer argument arrays when parameters may contain spaces or untrusted strings; command strings go through `/bin/sh -c` and need shell quoting. The callback result has `exitCode`, `stdout`, `stderr`, `timedOut`, `stdoutTruncated`, `stderrTruncated`. `noctalia.runAsync(argv)` without callback detaches the process. `noctalia.runStream(cmd, onLine)` runs a long-lived shell command; active streams stop on entry teardown. `noctalia.commandExists`, `noctalia.portalAvailable`, and `noctalia.getenv` support dependency checks.

## Native HTTP and streaming

```lua
local url = "https://api.example.test/items?q=" .. noctalia.string.urlEncode(query)
local accepted = noctalia.http({
  url = url,
  method = "GET",
  headers = { "Accept: application/json" },
}, function(result)
  if not result.ok or result.status ~= 200 then
    noctalia.log("Request failed: status=" .. tostring(result.status))
    return
  end
  local data, err = noctalia.json.decode(result.body)
  if not data then noctalia.log("Bad response JSON: " .. tostring(err)); return end
  -- check expected fields and ownership before publishing
end)
if not accepted then noctalia.log("Request could not be queued") end
```

Use `noctalia.httpStream(request, onLine, onClose)` (API ≥4) for SSE or line-based streams; it returns a stoppable handle or nil. Stream `onClose` fires once on terminal outcomes *except* after `handle.stop()`. Streaming callbacks can arrive after an old query, so check request generations/source identity before mutating UI or state. When disabled/offline or unauthorized, display meaningful state; do not rapidly reconnect in tight loops. `allow_insecure_tls` (API ≥7) disables certificate checks and is security-sensitive: prefer valid certs.

`noctalia.download(url, path, cb)` writes to a local file. Download images before passing the resulting file path to `ui.image`.

## Timers, calendar, sound, idle, layers

- `noctalia.formatTime` formats with shell tokens; timezone overload and `noctalia.timeFormat`/`dateFormat` need API ≥19.
- `noctalia.systemStats`, `noctalia.cpuCores`, `noctalia.nowMs` need API ≥12; extended network/disk details API ≥16.
- `noctalia.sound.load(name, path, callback)` then `.play(name)` need API ≥20. A successful enqueue does not guarantee decode success.
- `noctalia.idle.watch(seconds, callback[, options])`/`.unwatch(id)` need API ≥35 (unreleased in snapshot). Watches release automatically on entry teardown; max 8 watches per runtime.
- `noctalia.calendarEvents()` API ≥37 (unreleased in snapshot).
- `noctalia.layer.show(localId)`, `.hide(localId)`, `.configure(localId, props)` API ≥36 (unreleased); the local entry id has no colon/slash. Runtime `configure` uses camelCase keys even though the manifest uses snake_case.
- `noctalia.osd.show(icon, value, opts)` API ≥39 (unreleased).
- `noctalia.openColorPicker(initial, callback)` is separate from `ui.colorPicker` (API ≥41).
- Prefer `noctalia.togglePanel("author/plugin:panel")` over launching shell IPC. `noctalia.openSettings()` opens own plugin settings and requires API ≥15.

## Module discipline

Use `require("./lib/module.luau")` only at API ≥22. Modules are file-relative, must return a nonnil value, and have per-entry caches. No package loaders or fallback extension. Do not assume a successful module import shares memory with another entry.

## Reliability and safety review

Confirm: HTTP/network requests rate-limited; no secrets in logs/process argv; no unchecked JSON type casts; no shell injection; no writes to plugin source; async errors handled; generation guards for stale callbacks; cleanup is idempotent; compositor features/output selection accounted for; offline mode degrades safely. Consider backward compatibility of any newly used API; avoid opting into unreleased API without an explicit target host that supports it.
