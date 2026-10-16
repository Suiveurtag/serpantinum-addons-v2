#!/usr/bin/env python3
"""Build and apply a small Xcursor theme from a selected image."""

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageOps


HOME = Path.home()
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
ADDON = DATA / "serpantinum-addons-v2"
THEME = "SerpantinumCustomCursor"
SIZE = 32
CURSOR_DIR = DATA / "icons" / THEME / "cursors"
ENV_LUA = HOME / ".config/hypr/config/env.lua"
GTK_FILES = [HOME / ".config/gtk-3.0/settings.ini", HOME / ".config/gtk-4.0/settings.ini"]
BEGIN = "-- BEGIN serpantinum-addons-v2 custom cursor"
END = "-- END serpantinum-addons-v2 custom cursor"


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name, dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def backup(path):
    if not path.is_file():
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    destination = ADDON / "backups" / ("custom-cursor-" + stamp) / path.relative_to(HOME)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)


def xcursor_bytes(image):
    image = ImageOps.exif_transpose(image).convert("RGBA")
    image.thumbnail((SIZE, SIZE), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(image, (0, 0))
    pixels = []
    for red, green, blue, alpha in canvas.getdata():
        pixels.append((alpha << 24) | (red << 16) | (green << 8) | blue)

    image_type = 0xFFFD0002
    header = struct.pack("<4I", 0x72756358, 16, 1, 1)
    toc = struct.pack("<3I", image_type, SIZE, 28)
    chunk = struct.pack("<9I", 36, image_type, SIZE, 1, SIZE, SIZE, 0, 0, 0)
    return header + toc + chunk + struct.pack("<" + "I" * len(pixels), *pixels)


def make_theme(image_path):
    with Image.open(image_path) as image:
        if image.width * image.height > 60_000_000:
            raise ValueError("Selected image is too large")
        cursor = xcursor_bytes(image.copy())

    CURSOR_DIR.mkdir(parents=True, exist_ok=True)
    atomic_write(CURSOR_DIR / "left_ptr", cursor)
    for alias in ("default", "arrow", "top_left_arrow"):
        path = CURSOR_DIR / alias
        if path.is_symlink() or path.exists():
            path.unlink()
        path.symlink_to("left_ptr")
    index = "[Icon Theme]\nName=Serpantinum custom cursor\nComment=Cursor image selected in Serpantinum\nInherits=Adwaita\n"
    atomic_write(CURSOR_DIR.parent / "index.theme", index.encode())


def replace_env_block(text):
    block = (
        BEGIN + "\n"
        + "hl.env(\"XCURSOR_THEME\", " + json.dumps(THEME) + ")\n"
        + "hl.env(\"XCURSOR_SIZE\", " + json.dumps(str(SIZE)) + ")\n"
        + END
    )
    start = text.find(BEGIN)
    if start >= 0:
        end = text.find(END, start)
        if end < 0 or text.find(BEGIN, start + 1) >= 0:
            raise ValueError("Invalid custom cursor block in Hyprland env.lua")
        end += len(END)
        return text[:start] + block + text[end:]
    return text.rstrip() + "\n\n" + block + "\n"


def update_gtk(path):
    text = path.read_text() if path.exists() else ""
    lines = text.splitlines()
    if not lines:
        lines = ["[Settings]"]
    if not any(line.strip() == "[Settings]" for line in lines):
        lines.extend(["", "[Settings]"])
    start = next(index for index, line in enumerate(lines) if line.strip() == "[Settings]")
    end = next((index for index in range(start + 1, len(lines)) if line_is_section(lines[index])), len(lines))
    values = {"gtk-cursor-theme-name": THEME, "gtk-cursor-theme-size": str(SIZE)}
    section = lines[start + 1:end]
    found = set()
    updated = []
    for line in section:
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key not in values:
            updated.append(line)
        elif key not in found:
            updated.append(key + "=" + values[key])
            found.add(key)
    for key, value in values.items():
        if key not in found:
            updated.append(key + "=" + value)
    lines[start + 1:end] = updated
    new_text = ("\n".join(lines).rstrip() + "\n").encode()
    if path.is_file() and path.read_bytes() == new_text:
        return
    backup(path)
    atomic_write(path, new_text)


def line_is_section(line):
    return line.strip().startswith("[") and line.strip().endswith("]")


def apply(image_path):
    path = Path(image_path).expanduser().resolve(strict=True)
    try:
        make_theme(path)
    except (OSError, Image.DecompressionBombError) as error:
        raise ValueError("Could not read the selected cursor image: " + str(error)) from error

    env_text = ENV_LUA.read_text() if ENV_LUA.exists() else ""
    new_env_text = replace_env_block(env_text).encode()
    if not ENV_LUA.is_file() or ENV_LUA.read_bytes() != new_env_text:
        backup(ENV_LUA)
        atomic_write(ENV_LUA, new_env_text)
    for gtk_file in GTK_FILES:
        update_gtk(gtk_file)

    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", THEME], check=False, capture_output=True)
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(SIZE)], check=False, capture_output=True)
    if shutil.which("hyprctl"):
        subprocess.run(["hyprctl", "reload"], check=False, capture_output=True, text=True)
    print(json.dumps({"ok": True, "theme": THEME, "size": SIZE, "image": str(path)}))


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "apply":
        print("usage: custom_cursor.py apply IMAGE_PATH", file=sys.stderr)
        sys.exit(2)
    try:
        apply(sys.argv[2])
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
