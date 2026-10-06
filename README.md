# Serpantinum personal addons v2

Focused addons for the native Serpantinum Settings/Guide, independent of the retired v1 installer.

> **Personal project notice:** This is a personal project and may be unstable. Updates and ongoing maintenance are not guaranteed. Parts of it are developed with vibe coding, so review changes and test them in your own setup before relying on them.

- Addons: opt-in legacy calendar/clock and Mullvad DNS.
- Network: the same DNS switch, reflecting the active connection.
- Monitors: recovered v1 screen placement and snapping, resolution cards, rotation dial and refresh-rate slider, with native Guide scaling and an exact-coordinate alternative.
- Keybinds: recovered v1 keycaps, sliding edit control, expandable editor, shortcut recording, add/delete/save, and search. Existing Lua actions, options and generated workspace bindings are preserved.
- Theme: Matugen, Vibrant and Vivid use the shell's original wallpaper theme tiles, colors, selection and animations.
- About stays last. Dragging Settings uses its title area; dragging an individual monitor affects the preview only, until Apply.

## Install

Run `python3 install.py` from the repository root, then `serpantinum reload`.

Requires the installed Serpantinum shell, Hyprland Lua configuration, NetworkManager, systemd-resolved, jq, matugen and Python with Pillow. Installation retains dated shell backups in `~/.local/share/serpantinum-addons-v2/backups/`. Reinstall after updating upstream; the patcher verifies known anchors before changing the shell.

Monitor changes apply to `~/.config/hypr/config/monitors.lua`. Keyboard edits update literal bindings in `~/.config/hypr/config/keybinds.lua`; generated workspace loops remain intact. Both backends save backups and restore the previous file if reloading reports a configuration error. Conflicting external keybind edits require reloading the editor.

Vibrant selects actual sampled wallpaper colors as accents. Vivid retains their hue while increasing saturation and brightness. Shell surfaces and text retain the upstream palette for readability; synthetic Matugen templates update application colors alongside the shell. Matugen mode follows the native generator.

## Validation

Run `python3 -m unittest discover -s tests -v` with Serpantinum installed. The tests cover native theme integration, sidebar ordering/idempotence, preservation of Lua binding actions/flags/generated loops, and external-edit conflicts.

The revised pages were also checked in the live shell. An actual pointer drag moved a monitor preview without moving Settings, and a keybind row expanded through real pointer input. These interaction checks did not save new monitor or keybind configurations.
