#!/usr/bin/env python3
"""Build Clawd's sprite strips from the ASCII frames in scripts/clawd/frames/<anim>.txt.
'.' transparent, '#' body, 'o' eyes, 'z' cream props (sleep z, ✻, keyboard, !), 'h' pink hearts; frames separated by a blank line.
hand.png (the petpet hand, drawn over Clawd in sync with his frames) is cut out of scripts/clawd/hand-pet.gif.
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
PALETTE = {'.': (0, 0, 0, 0), '#': (0xD9, 0x77, 0x57, 255), 'o': (0, 0, 0, 255), 'z': (0xF0, 0xEE, 0xE6, 255), 'h': (0xEC, 0x5B, 0x86, 255)}
# name: (fps, loop); order is the manifest order
ANIMS = {
    'idle': (2, True), 'blink': (12, False), 'look_left': (2, False), 'look_right': (2, False),
    'look_up': (2, False), 'walk': (8, True), 'turn': (12, False), 'sit': (2, True), 'sleep': (3, True),
    'drag': (6, True), 'fall': (8, True), 'land': (10, False), 'spawn': (10, False),
    'think': (6, False), 'work': (6, True), 'oops': (10, False), 'alert': (6, True), 'happy': (10, False),
    'petpet': (20, True), 'petpetheart': (20, True),
}
HAND = Path(__file__).resolve().parent/'hand-pet.gif'
HAND_SCALE = 3  # source frames are 474x498, Clawd shows the hand at most ~16 px x8


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


def hand():
    """Cut the hand out of the gif's near-black background: flood from the borders, then drop the dark specks it leaves."""
    gif = Image.open(HAND)
    out = []
    for i in range(gif.n_frames):
        gif.seek(i)
        f = gif.convert('RGBA')
        w, h = f.size
        px = f.load()
        seen = set()
        stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
        while stack:
            x, y = stack.pop()
            if (x, y) in seen or not (0 <= x < w and 0 <= y < h) or max(px[x, y][:3]) > 95:
                continue
            seen.add((x, y))
            px[x, y] = (0, 0, 0, 0)
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        seen = set()
        for sy in range(h):
            for sx in range(w):
                if (sx, sy) in seen or not px[sx, sy][3]:
                    continue
                comp, stack = [], [(sx, sy)]
                seen.add((sx, sy))
                while stack:
                    x, y = stack.pop()
                    comp.append((x, y))
                    for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                        if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and px[n][3]:
                            seen.add(n)
                            stack.append(n)
                if len(comp) < 500:
                    for p in comp:
                        px[p] = (0, 0, 0, 0)
        out.append(f.convert('RGBa').resize((w // HAND_SCALE, h // HAND_SCALE), Image.LANCZOS).convert('RGBA'))
    fw, fh = out[0].size
    img = Image.new('RGBA', (fw * len(out), fh))
    for i, f in enumerate(out):
        img.paste(f, (i * fw, 0))
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=False, compress_level=9)
    return buf.getvalue(), {'file': 'hand.png', 'frames': len(out), 'w': fw, 'h': fh}


def build():
    files = {}
    manifest = {'frame': {'w': W, 'h': H}, 'animations': {}}
    for name, (fps, loop) in ANIMS.items():
        blocks = frames(name)
        files[f'{name}.png'] = png(blocks)
        manifest['animations'][name] = {'file': f'{name}.png', 'frames': len(blocks), 'fps': fps, 'loop': loop}
    files['hand.png'], manifest['hand'] = hand()
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
