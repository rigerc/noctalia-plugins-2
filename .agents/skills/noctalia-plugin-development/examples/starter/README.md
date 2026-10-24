# Demo

A minimal **Noctalia v5+ native Luau plugin** (`starter` starter).

## Install and test

Copy this plugin directory under `$XDG_DATA_HOME/noctalia/plugins/demo/`, or add a `path` source to the **parent repository directory**. Then enable it in Noctalia Settings → Plugins or with:

```sh
noctalia msg plugins enable acme/demo
```

Run local checks:

```sh
python3 /path/to/noctalia-plugin-development/scripts/validate_plugin.py .
noctalia plugins lint .   # available in Noctalia builds exposing offline plugin lint
```

For a bar widget, place `acme/demo:status` on a bar. Click it to open `acme/demo:panel`.

## Notes

- Set `plugin_api` to the *oldest required* feature level, not the latest advertised.
- Files run in isolated Luau entry VMs; cross-entry values use `noctalia.state`.
- Settings labels live under `translations/en.json`.
- This generated plugin was statically scaffolded; verify in a matching live Noctalia/Wayland session.
