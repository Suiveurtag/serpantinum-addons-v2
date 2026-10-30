# Clawd, Claude Code desktop pet

Clawd is the Claude Code pixel mascot: a flat `#D97757` block with two black
eyes, arm stubs and four short legs, drawn from PNG strips at an integer scale
with no smoothing. He lives in Settings → Addons → General, in a terminal-style
card. Off by default; OFF unloads every window, timer, socket and process.

## Controls

| Control | Behaviour |
| --- | --- |
| `Super+Shift+L` | Toggle Clawd (`addonsV2Clawd`). Search `clawd` in Keybinds to change it; the installer preserves edits |
| Left drag | Pick him up; he follows the pointer, across monitors |
| Release | Falls to the floor of the screen under the drop point, then lands |
| Left click | Small reaction; wakes him up |
| Right click | ASCII menu: `> sleep` / `> wake`, `> hide` (turns Clawd off), `> settings`. Escape or an outside click closes it |

Left alone he walks along the bottom of his screen (above the bar's reserved
area), blinks, looks toward the pointer, sits, and falls asleep after the
configured idle delay. Shell performance mode cuts idle actions and stops
pointer polling.

IPC, target `clawd`:

```sh
quickshell -p ~/.local/share/serpantinum/src/quickshell/Shell.qml ipc call clawd toggle
quickshell -p … ipc call clawd appear   # not "show": the quickshell CLI reads it as `ipc show`
quickshell -p … ipc call clawd hide
quickshell -p … ipc call clawd play walk   # "ok", "unknown" or "off"
```

`play` accepts any animation name from `clawd.json` (`idle`, `blink`,
`look_left`, `look_right`, `look_up`, `walk`, `turn`, `sit`, `sleep`, `drag`,
`fall`, `land`, `spawn`); loops play for about 3 s, then normal behaviour resumes.

## Settings card

| Row | Setting |
| --- | --- |
| Enable | `addonsV2Clawd`, default off |
| Scale | `addonsV2ClawdScale`, 2–8× pixels, default 4 |
| Walk speed | `addonsV2ClawdSpeed`: calm, normal, active |
| Sleep after | `addonsV2ClawdSleep`, 1–60 minutes, default 5 |
| Summon on this screen | Respawns him on the focused monitor (disabled while off) |
| Shortcut | Opens Keybinds; search `clawd` there to change it |

Settings are shared with the separate Settings process through `settings.json`,
so the card works in the Settings app and in the integrated `Super+Shift+P` panel.

## Sprites

Frames are ASCII art in `scripts/clawd/frames/<animation>.txt`. After editing:

```sh
python3 scripts/clawd/sprites.py          # writes payload/clawd/sprites/*.png + clawd.json
python3 scripts/clawd/sprites.py --check  # exits 1 if committed outputs are stale
```

Output is deterministic. Palette: transparent, body `#D97757`, eyes `#000000`,
and cream `#F0EEE6` only for the sleep "z". Frames face right; left is mirrored
at runtime.

## Install and remove

`python3 install.py` installs `payload/clawd/` to `quickshell/clawd/`, registers
the types in the root `qmldir`, hosts `AddonClawd` in `Shell.qml` and adds the
`Super+Shift+L` bind to `keybinds.lua`. `python3 install.py --without-clawd`
removes only Clawd's files, blocks and bind, with dated backups; other addons
are untouched.

## Validation

1. `python3 scripts/clawd/sprites.py --check` and
   `python3 -m unittest discover -s tests -v`.
2. Install, enable the card switch: Clawd spawns at the bottom of the focused
   monitor. `Super+Shift+L` twice hides and shows him.
3. Drag him to another monitor (including ones with negative offsets) and
   release: he falls to that screen's floor. The rest of the desktop stays
   click-through.
4. Right-click: menu opens; Escape closes it; `> settings` opens Settings.
5. Change scale and speed in the card: the running pet follows immediately.
   Summon from Settings on another monitor.
6. Turn Clawd off: `qs-addon-clawd` layers disappear (`hyprctl layers`).
