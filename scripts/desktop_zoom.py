#!/usr/bin/env python3
"""Animate live compositor zoom; restore the session on close, EOF or SIGTERM."""
import json
import math
import os
from pathlib import Path
import select
import signal
import socket
import sys
import time


def request(path, command):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(1)
        client.connect(str(path))
        client.sendall(command.encode())
        chunks = []
        while chunk := client.recv(4096):
            chunks.append(chunk)
    return b''.join(chunks).decode()


def clamp(value):
    value = float(value)
    if not math.isfinite(value):
        raise ValueError('Invalid zoom factor')
    return max(1.0, min(6.0, value))


def configure(path, values):
    fields = ','.join(key + '=' + (str(value).lower() if isinstance(value, bool) else f'{value:.5f}')
                      for key, value in values.items())
    reply = request(path, 'eval hl.config({cursor={' + fields + '}})')
    if reply.strip() != 'ok':
        raise RuntimeError(reply)


def main():
    path = Path(os.environ['XDG_RUNTIME_DIR']) / 'hypr' / os.environ['HYPRLAND_INSTANCE_SIGNATURE'] / '.socket.sock'
    saved = {}
    for key, kind in [('zoom_factor', 'float'), ('zoom_rigid', 'bool'), ('zoom_detached_camera', 'bool')]:
        saved[key] = json.loads(request(path, 'j/getoption cursor:' + key))[kind]
    stopped = False

    def stop(*_):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    current = start = target = saved['zoom_factor']
    started = time.monotonic()
    closing = False
    buffer = b''
    try:
        configure(path, {'zoom_rigid': True, 'zoom_detached_camera': False})
        point = json.loads(request(path, 'j/cursorpos'))
        print(json.dumps({'ready': True, 'factor': current, 'x': point['x'], 'y': point['y']}), flush=True)
        while not stopped:
            if select.select([sys.stdin], [], [], 1 / 60)[0]:
                data = os.read(sys.stdin.fileno(), 4096)
                if not data:
                    break
                buffer += data
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    message = json.loads(line)
                    closing = message.get('close', False)
                    start = current
                    target = saved['zoom_factor'] if closing else clamp(message['factor'])
                    started = time.monotonic()
            progress = min(1.0, (time.monotonic() - started) / 0.28)
            value = start + (target - start) * (1 - (1 - progress) ** 3)
            if abs(value - current) > 0.00001:
                configure(path, {'zoom_factor': value})
                current = value
                print(json.dumps({'factor': current}), flush=True)
            if closing and progress == 1:
                break
    finally:
        configure(path, saved)


if __name__ == '__main__':
    try:
        main()
    except (OSError, KeyError, ValueError, RuntimeError) as error:
        print(f'Desktop zoom: {error}', file=sys.stderr)
        sys.exit(1)
