# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
"""Render the app icon from the bike photo: the bike in its own colours on a light background.

    uv run design/make_icon.py design/fiido-c21.png FiidoRide/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

import sys

from PIL import Image, ImageDraw, ImageOps

SIZE = 1024
BIKE_WIDTH = 900
BACKGROUND_TOP = (255, 255, 255)
BACKGROUND_BOTTOM = (222, 226, 232)
WHITE_CUTOFF = 235


def cutout(photo: Image.Image) -> Image.Image:
    """The bike on a transparent background: the whiter a pixel, the more transparent."""
    gray = ImageOps.grayscale(photo)
    alpha = gray.point(lambda v: 0 if v >= WHITE_CUTOFF else min(255, (WHITE_CUTOFF - v) * 6))
    bike = photo.convert("RGBA")
    bike.putalpha(alpha)
    return bike.crop(alpha.getbbox())


def background() -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(image)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        draw.line([(0, y), (SIZE, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BACKGROUND_TOP, BACKGROUND_BOTTOM)))
    return image


def main(source: str, destination: str) -> None:
    bike = cutout(Image.open(source).convert("RGB"))
    bike = bike.resize((BIKE_WIDTH, round(bike.height * BIKE_WIDTH / bike.width)), Image.LANCZOS)
    icon = background()
    icon.paste(bike, ((SIZE - bike.width) // 2, (SIZE - bike.height) // 2 + 30), mask=bike)
    icon.save(destination)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
