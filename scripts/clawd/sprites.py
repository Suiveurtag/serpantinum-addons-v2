#!/usr/bin/env python3
"""Build Clawd's sprite strips from the ASCII frames in scripts/clawd/frames/<anim>.txt.
'.' transparent, '#' body, 'o' eyes, 'z' sleep z; frames separated by a blank line.
Usage: sprites.py [--check]  (--check exits 1 when payload/clawd/sprites differs from the frames)"""
import io
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FRAMES = Path(__file__).resolve().parent/'frames'
OUT = ROOT/'payload/clawd/sprites'
W, H = 21, 14
PALETTE = {'.': (0, 0, 0, 0), '#': (0xD9, 0x77, 0x57, 255), 'o': (0, 0, 0, 255), 'z': (0xF0, 0xEE, 0xE6, 255)}
# name: (fps, loop); order is the manifest order
ANIMS = {
    'idle': (2, True), 'blink': (12, False), 'look_left': (2, False), 'look_right': (2, False),
    'look_up': (2, False), 'walk': (8, True), 'turn': (12, False), 'sit': (2, True), 'sleep': (3, True),
    'drag': (6, True), 'fall': (8, True), 'land': (10, False), 'spawn': (10, False),
}


def frames(name):
    path = FRAMES/f'{name}.txt'
    blocks = [b.split('\n') for b in path.read_text().strip('\n').split('\n\n')]
    for i, rows in enumerate(blocks):
        if len(rows) != H or any(len(r) != W for r in rows):
            sys.exit(f'{path}: frame {i} is not {W}x{H}')
        bad = set(''.join(rows)) - set(PALETTE)
        if bad:
            sys.exit(f'{path}: frame {i} uses unknown pixels {sorted(bad)}')
    return blocks


def png(blocks):
    img = Image.new('RGBA', (W * len(blocks), H))
    img.putdata([PALETTE[c] for y in range(H) for i in range(len(blocks)) for c in blocks[i][y]])
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=False, compress_level=9)  # no metadata chunks: bytes depend only on pixels
    return buf.getvalue()


def build():
    files = {}
    manifest = {'frame': {'w': W, 'h': H}, 'animations': {}}
    for name, (fps, loop) in ANIMS.items():
        blocks = frames(name)
        files[f'{name}.png'] = png(blocks)
        manifest['animations'][name] = {'file': f'{name}.png', 'frames': len(blocks), 'fps': fps, 'loop': loop}
    files['clawd.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    return files


def same(name, data):
    old = (OUT/name).read_bytes()
    if not name.endswith('.png'):
        return old == data
    # pixels, not bytes: another zlib build may compress the same image differently
    a, b = (Image.open(io.BytesIO(d)) for d in (old, data))
    return a.mode == b.mode and a.size == b.size and a.tobytes() == b.tobytes()


def main():
    files = build()
    if '--check' in sys.argv[1:]:
        stale = [n for n, data in files.items() if not (OUT/n).is_file() or not same(n, data)]
        extra = [p.name for p in OUT.glob('*') if p.name not in files] if OUT.is_dir() else []
        if stale or extra:
            print('clawd sprites out of date: ' + ', '.join(stale + extra) + ' (run scripts/clawd/sprites.py)')
            sys.exit(1)
        return
    OUT.mkdir(parents=True, exist_ok=True)
    for n, data in files.items():
        (OUT/n).write_bytes(data)


if __name__ == '__main__':
    main()
