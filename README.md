# Noctalia plugins — rigerc

Custom Noctalia **v5+** plugin source for `rigerc/noctalia-plugins-2`.

## Included plugins

- `rigerc/example` — demonstration of bar widgets, a service, shortcut, launcher provider, floating panels, and a layer.

- `rigerc/t3` — T3 Code monitor with a bar widget and dashboard.
- `rigerc/bindpeek` — native shortcut cheat sheet with live modifier overlay and animated keycaps; requires Noctalia v5.4.0+ (plugin API 43) and the separate Bindpeek CLI/watch service. See [setup](bindpeek/README.md).

This is adapted from the MIT-licensed `noctalia/example` reference plugin published by the [Noctalia team](https://github.com/noctalia-dev/official-plugins). The original source and authorship are acknowledged; changing the plugin ID avoids overriding the official copy.

**Requires** a Noctalia v5 build supporting plugin API 36 or later. The example is a developer demonstration; Bindpeek and T3 are separate functional plugins.

## Install from GitHub

After the files have been pushed to `https://github.com/rigerc/noctalia-plugins-2`, register this source:

```sh
noctalia msg plugins source add rigerc git git@github.com:rigerc/noctalia-plugins-2.git
noctalia msg plugins enable rigerc/example
noctalia msg plugins list
```

The repository is currently private. Configure SSH access to GitHub (`ssh -T git@github.com`) so Noctalia can fetch it; alternatively, make the repository public and register the HTTPS URL:

```sh
noctalia msg plugins source add rigerc git https://github.com/rigerc/noctalia-plugins-2
```

Add the **Example / hello** widget from **Settings → Bar**, or open a demo panel:

```sh
noctalia msg panel-toggle rigerc/example:panel
```

## Install from an unpacked directory instead

```sh
noctalia msg plugins source add rigerc-dev path "$HOME/dev/noctalia-plugins-2"
noctalia msg plugins enable rigerc/example
```

Do not register both sources with the same name at once; `source list` and `source remove <name>` manage registrations.

## Develop

Edit `example/*.luau` to hot-reload plugin scripts. Changes to `plugin.toml` require a config reload. The editor API reference is `noctalia.d.luau` (see `.vscode/settings.json`).

Validate the source with:

```sh
python3 .github/workflows/validate-plugins.py
python3 -m unittest discover -s .github/workflows -p 'test_validate_plugins.py'
```

Plugin structure and commands follow the [Noctalia v5 plugin guide](https://docs.noctalia.dev/noctalia/plugins/).
