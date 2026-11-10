# Bindpeek for Noctalia v5

A native Noctalia shortcut overlay, based on [Bindpeek](https://github.com/Maik-0000FF/bindpeek) and [rigerc's animated keycap contribution, PR #6](https://github.com/rigerc/bindpeek/pull/6).

**Hold a modifier to see what it can do.** The overlay uses Noctalia's layer-shell surface and palette. It consumes only the existing Bindpeek command-line modifier reports and shortcut listings. The plugin never opens input devices, intercepts keyboard events, or executes shortcut commands.

## Plugin

Manifest ID: `rigerc/bindpeek`.

The plugin includes the `watch` background service for Bindpeek CLI events, the `overlay` non-interactive layer, the `viewer` searchable panel, the `status` bar widget, and the `toggle` control-center shortcut.

## Usage

Hold SUPER, CTRL, ALT, or another supported modifier to reveal reachable shortcuts; release the modifiers to dismiss the passive overlay. Use the bar widget or control-center tile to pin an all-shortcuts preview, and open the searchable viewer when you need the complete binding list.

## Settings

Adjust automatic activation, presentation layout, hold delay, deeper modifier matches, lone-Shift handling, and reduced-motion keycap animation in Bindpeek plugin settings. These options are persisted by Noctalia.
## Requirements

- Noctalia v5.4.0 or newer with plugin API 43 support.
- An installed Bindpeek CLI on PATH in the Noctalia session.
- The original Bindpeek socket-activated keyboard reader properly installed. Verify that the commands below work in a terminal:

      bindpeek --list
      bindpeek --keys

- A compositor supported by Bindpeek shortcut discovery: Hyprland, sway, mango, or KDE Plasma.

Do not start the standalone Bindpeek editor/overlay alongside this plugin unless you intentionally want two overlays. Keep its CLI and its privileged systemd reader installed. The plugin makes no privileged system changes and does not require membership in the input group.

## Install and open

If the repository is not already a plugin source, register it first:

    noctalia msg plugins source add rigerc git https://github.com/rigerc/noctalia-plugins-2
    noctalia msg plugins enable rigerc/bindpeek

You can also use a local path source when developing:

    noctalia msg plugins source add rigerc-dev path "$HOME/dev/noctalia-plugins-2"

Use the Bindpeek bar widget's left click to open the searchable shortcut viewer, or right click to pin/unpin the passive overlay. A control-center shortcut is also available.

## IPC

    noctalia msg plugin rigerc/bindpeek:watch all toggle
    noctalia msg plugin rigerc/bindpeek:watch all refresh
    noctalia msg plugin rigerc/bindpeek:watch all hide
    noctalia msg panel-toggle rigerc/bindpeek:viewer

The passive overlay has no keyboard interactivity or pointer region and reserves no screen space. Modifier release dismisses the automatic overlay; a pinned preview remains until toggled off.

## Layouts and animation

Select List, Keyboard, Quick actions, or Radial actions in the plugin's settings. The four views show grouped matching actions, an illustrated US-layout keyboard, short action cards with a compact keyboard, or five cards around a modifier hub. The searchable viewer contains the complete list.

The hold delay, deep modifier matches, lone-Shift behavior, and decorative motion are all configurable. Keycap halos, accent surfaces, borders, and the overlay fade reproduce the intent of PR #6 within released Noctalia APIs. Full geometric transform animations require unreleased plugin API 52, so the current version uses API 43-compatible visual transitions instead.

## Limitations and security

- The Bindpeek CLI reports held modifiers, not key identities or typed characters. There is no keystroke history or command execution.
- The CLI does not report the shortcut-taken event: unlike the original native overlay, this plugin dismisses on modifier release rather than immediately on non-modifier keypress.
- It parses the human-readable columns from Bindpeek --list; future changes to that format may need an adapter update.
- Unusual key names and non-US keyboard layouts still appear in the list and viewer, but not necessarily at their physical location on the illustrated keyboard.
- The service refreshes shortcut bindings before each new modifier-hold appearance and reconnects to a restarted watcher approximately every two seconds.
- For a full-featured input-capturing interactive keyboard simulator, use the separate Bindpeek UI; this layer intentionally never captures focus.

## Manual verification

1. Confirm both CLI commands above work.
2. Hold SUPER, add CTRL and then release; check automatic appearance, filtering, and dismissal without stealing focus.
3. Select each of the four layouts and check that cards and keycaps fit on screen.
4. Disable animations and confirm the highlights remain legible.
5. Edit a compositor binding, then hold a modifier again; check that the updated binding appears.
6. Stop and restart the Bindpeek watcher; confirm the overlay hides rather than sticking open.
7. Test the pin toggle, viewer search, bar widget, control-center shortcut and IPC.

## Attribution and licensing

**GPL-3.0-or-later.** This native implementation recreates behavior from [Maik-0000FF/bindpeek](https://github.com/Maik-0000FF/bindpeek) (GPL-3.0-or-later) and the [rigerc keycap styling PR](https://github.com/rigerc/bindpeek/pull/6). The privileged keyboard reader is not bundled, forked, replaced, or modified by this plugin.
