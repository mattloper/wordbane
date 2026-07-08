"""Bake the AI art into a committed, web-usable folder.

Generates every (kind, style, subject) once — reusing the on-disk cache, so it's
cheap to re-run — and writes a DOWNSCALED png to a predictable path:

    shared_data/art/<kind>/<style>/<subject>.png

That layout is what the web build loads directly (no daemon, no hashes), small
enough to commit and hand to someone. The same run also warms the full-size Godot
cache as a side effect.

    uv run python -m wordplay_art.bake                       # all styles, 256px
    uv run python -m wordplay_art.bake --styles storybook    # just one
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from . import artwork

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "shared_data" / "art"


def _creatures() -> list[str]:
    pools = json.loads((REPO / "shared_data" / "word_bank.json").read_text())["pools"]["creature"]
    return [w["text"] for w in pools.get("negative", []) + pools.get("neutral", [])]


def _boons() -> list[str]:
    rules = json.loads((REPO / "shared_data" / "rules.json").read_text())
    return [b["id"] for b in rules["boons"]["catalog"]]


def _jobs() -> list[tuple[str, str]]:
    jobs = []
    for c in _creatures():
        jobs.append(("creature", c))   # the monster
        jobs.append(("tombstone", c))  # its grave
    for b in _boons():
        jobs.append(("boon", b))
    return jobs


GAME_NAME = "wordbane"  # the logo's subject; change here if the game is renamed


def _export(src_png: Path, dst: Path, size: int) -> None:
    img = Image.open(src_png)
    if size < img.width:
        img = img.resize((size, size), Image.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Bake AI art into shared_data/art/ for the web build.")
    p.add_argument("--model", default="flux_2_klein_9b_q8p.ckpt")
    p.add_argument("--size", type=int, default=256, help="downscaled output size (px)")
    p.add_argument("--logo-size", type=int, default=512, help="logo size (bigger, for legible text)")
    p.add_argument("--styles", nargs="*", default=sorted(artwork.STYLES))
    p.add_argument("--port", type=int, default=7859, help="Draw Things gRPC port")
    a = p.parse_args(argv)

    jobs = _jobs()
    total = len(a.styles) * (len(jobs) + 1)  # +1 title logo per style
    n = 0
    for style in a.styles:
        for kind, subject in jobs:
            n += 1
            print(f"[{n}/{total}] {style}/{kind}/{subject} …", flush=True)
            try:
                src = artwork.image(kind, subject, style=style, model=a.model, port=a.port)
                _export(src, OUT / kind / style / f"{subject}.png", a.size)
            except Exception as e:  # noqa: BLE001
                print(f"   !! {e}", flush=True)
        # the game-title logo for this skin (one per style -> art/logo/<style>.png)
        n += 1
        print(f"[{n}/{total}] {style}/logo …", flush=True)
        try:
            src = artwork.image("logo", GAME_NAME, style=style, model=a.model, port=a.port)
            _export(src, OUT / "logo" / f"{style}.png", a.logo_size)
        except Exception as e:  # noqa: BLE001
            print(f"   !! {e}", flush=True)
    print(f"DONE -> {OUT}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
