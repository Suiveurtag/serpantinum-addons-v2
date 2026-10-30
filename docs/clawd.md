# Clawd, Claude Code desktop pet

Clawd is the Claude Code pixel mascot: a flat `#D97757` block with two black
eyes, arm stubs and four short legs, drawn from PNG strips at an integer scale
with no smoothing. He lives in Settings → Addons → General, in a terminal-style
card. Off by default; OFF unloads every window, timer and the cursor socket. Only
the hook socket stays, so he knows what your agents are doing when he comes back.

## Controls

| Control | Behaviour |
| --- | --- |
| `Super+Shift+L` | Toggle Clawd (`addonsV2Clawd`). Search `clawd` in Keybinds to change it; the installer preserves edits |
| Left drag | Pick him up; he follows the pointer, across monitors |
| Release | Falls to the floor of the screen under the drop point, then lands |
| Left click | Small reaction; wakes him up |
| Middle click | Petpet: a hand pets him for ~3 s (`> <` eyes); middle click again while petted for `^ ^` eyes and hearts |
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
`fall`, `land`, `spawn`, `think`, `work`, `oops`, `alert`, `happy`, `petpet`, `petpetheart`); loops play for about 3 s, then normal behaviour resumes.

## Claude Code and Codex

The card's `hooks` row connects each agent (`[ ] claude · [ ] codex`). Nothing touches
`~/.claude/settings.json` or `~/.codex/hooks.json` before you click; Codex then asks
you to trust the new hooks. The same thing from a terminal:

```sh
python3 ~/.local/share/serpantinum-addons-v2/scripts/clawd/hooks.py <status|install|uninstall> <claude|codex>
```

It adds one group per event next to the existing ones (Capri's included), writes a
`<file>.clawd-backup-<date>` before every change, and removes only commands running
`clawd-hook.js`. The hook (`scripts/clawd/hooks/clawd-hook.js`, node) sends one JSON line
`{agent, event, session_id, tool_name, notification_type, dir}` to
`$XDG_RUNTIME_DIR/serpantinum/clawd.sock`. No prompts, tool inputs or replies. It always
exits 0 within 500 ms and does nothing when the shell is not running.

| Event | Clawd |
| --- | --- |
| Prompt submitted | `think`, then `work` (typing) in place while the turn runs |
| Tool failed | `oops`, then back to `work` |
| Permission request | `alert` (hops) + `⚠ permission · <dir>` until that session moves on |
| Idle prompt / Codex asks a question | `… attend · <dir>` for 8 s |
| Turn finished | `happy` + `✓ terminé · <dir>` for 8 s |
| Session start | `spawn` |

Several sessions merge: alert beats work beats normal life. A session with no event for
2 minutes is forgotten, except one waiting for a permission. Click a bubble to close it.

## Settings card

| Row | Setting |
| --- | --- |
| Enable | `addonsV2Clawd`, default off |
| Scale | `addonsV2ClawdScale`, 2–8× pixels, default 4 |
| Walk speed | `addonsV2ClawdSpeed`: calm, normal, active |
| Sleep after | `addonsV2ClawdSleep`, 1–60 minutes, default 5 |
| Summon on this screen | Respawns him on the focused monitor (disabled while off) |
| Shortcut | Opens Keybinds; search `clawd` there to change it |
| Hooks | Connect / disconnect Claude Code and Codex |

Settings are shared with the separate Settings process through `settings.json`,
so the card works in the Settings app and in the integrated `Super+Shift+P` panel.

## Sprites

Frames are ASCII art in `scripts/clawd/frames/<animation>.txt`. After editing:

```sh
python3 scripts/clawd/sprites.py          # writes payload/clawd/sprites/*.png + clawd.json
python3 scripts/clawd/sprites.py --check  # exits 1 if committed outputs are stale
```

Output is deterministic. Palette: transparent, body `#D97757`, eyes `#000000`,
and cream `#F0EEE6` for small props (sleep "z", ✻, keyboard, "!"), pink `#EC5B86` for petpet hearts. Frames face right; left is mirrored
at runtime. `hand.png` (the petpet hand, 7 frames frame-locked to `petpet*`) is cut out of
`scripts/clawd/hand-pet.gif`'s black background by the same script; its size is in `clawd.json` → `hand`.

## Install and remove

`python3 install.py` installs `payload/clawd/` to `quickshell/clawd/`, registers
the types in the root `qmldir`, hosts `AddonClawd` in `Shell.qml` and adds the
`Super+Shift+L` bind to `keybinds.lua`. `python3 install.py --without-clawd`
removes only Clawd's files, blocks, bind and hooks (both agents), with dated backups;
other addons are untouched.

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
7. Connect Claude in the card, start a new session, send a prompt: think → work →
   happy + bubble. Same for Codex (trust the hooks first). A permission prompt
   makes him hop with `⚠ permission`.
