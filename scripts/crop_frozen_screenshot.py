#!/usr/bin/env python3
"""Crop a screenshot selection from the image already frozen by the overlay."""
import sys
from PIL import Image


def main(source_path, geometry, screen_size, output_path):
    try:
        position, dimensions = geometry.split(maxsplit=1)
        x, y = (int(value) for value in position.split(",", 1))
        width, height = (int(value) for value in dimensions.split("x", 1))
        logical_width, logical_height = (int(value) for value in screen_size.split("x", 1))
        if min(width, height, logical_width, logical_height) <= 0:
            raise ValueError("selection and screen dimensions must be positive")
    except (ValueError, TypeError) as error:
        raise SystemExit(f"Invalid frozen screenshot geometry: {error}")

    with Image.open(source_path) as frozen:
        scale_x = frozen.width / logical_width
        scale_y = frozen.height / logical_height
        left = round(x * scale_x)
        top = round(y * scale_y)
        right = round((x + width) * scale_x)
        bottom = round((y + height) * scale_y)
        if left < 0 or top < 0 or right > frozen.width or bottom > frozen.height:
            raise SystemExit("Frozen screenshot selection falls outside the captured monitor")
        if right <= left or bottom <= top:
            raise SystemExit("Frozen screenshot selection is empty")
        frozen.crop((left, top, right, bottom)).save(output_path, format="PNG")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("Usage: crop_frozen_screenshot.py IMAGE 'X,Y WxH' SCREEN_WxSCREEN_H OUTPUT")
    main(*sys.argv[1:])
