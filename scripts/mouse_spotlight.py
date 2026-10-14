#!/usr/bin/env python3
"""Stream global logical cursor coordinates while the spotlight is visible."""
import json
import os
from pathlib import Path
import socket
import sys
import time


def query_cursor(path):
    # Use Hyprland's local IPC directly: no subprocess for each animation frame.
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(1)
        client.connect(str(path))
        client.sendall(b'j/cursorpos')
        chunks = []
        while chunk := client.recv(4096):
            chunks.append(chunk)
    data = json.loads(b''.join(chunks))
    return {'x': float(data['x']), 'y': float(data['y'])}


def main():
    signature = os.environ['HYPRLAND_INSTANCE_SIGNATURE']
    path = Path(os.environ['XDG_RUNTIME_DIR']) / 'hypr' / signature / '.socket.sock'
    previous = None
    while True:
        started = time.monotonic()
        point = query_cursor(path)
        if point != previous:
            print(json.dumps(point), flush=True)
            previous = point
        time.sleep(max(0, 1 / 60 - (time.monotonic() - started)))


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
    except (OSError, KeyError, ValueError) as error:
        print(f'Mouse spotlight: {error}', file=sys.stderr)
        sys.exit(1)
