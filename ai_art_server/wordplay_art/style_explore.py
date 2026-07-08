"""Render a small matrix of visual styles x monsters-with-weapons, so we can pick
one coherent style for the game. Same seed per monster -> only the style changes.

Uses the *canonical* styles + prompt builder from `artwork`, so what you preview
here is exactly what the game generates.

    uv run python -m wordplay_art.style_explore

Writes to ~/Desktop/wordplay_art_styles/<style>/<monster>.png
"""
from __future__ import annotations

import os

from PIL import Image

from . import artwork
from .client import decode_image, generate

OUT_ROOT = os.path.expanduser("~/Desktop/wordplay_art_styles")

# Creatures drawn from the game's roster (kind=creature); fixed seed per compare.
CREATURES = ["dragon", "goblin", "wolf"]


def main() -> None:
    styles = list(artwork.STYLES)
    total = len(styles) * len(CREATURES)
    n = 0
    for style in styles:
        d = os.path.join(OUT_ROOT, style)
        os.makedirs(d, exist_ok=True)
        for creature in CREATURES:
            n += 1
            print(f"[{n}/{total}] {style} / {creature} …", flush=True)
            prompt = artwork.build_prompt("creature", creature, style)
            imgs = generate(prompt=prompt, model=artwork.MODEL,
                            negative_prompt=artwork.NEGATIVE, seed=42)
            if not imgs:
                print("   !! no image returned", flush=True)
                continue
            img = decode_image(imgs[0]).resize((512, 512), Image.LANCZOS)
            img.save(os.path.join(d, f"{creature}.png"))
    print(f"DONE -> {OUT_ROOT}", flush=True)


if __name__ == "__main__":
    main()
