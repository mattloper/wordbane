"""Styled, cached artwork for Wordplay.

Every piece is a (kind, subject) pair — e.g. portrait/"a dragon wielding an axe",
boon/tough, tombstone/dragon — turned into a styled prompt by one template per KIND.
Portraits are built from NOUNS only (creature + weapon nouns, no adjectives), so an
enemy's picture caches per (creature, weapons) instead of per full sentence.

Results are cached on disk, content-addressed by (model / config-hash / prompt-hash),
with a stable seed per prompt (same subject + style -> same picture). Changing a
style suffix changes the prompt, hence the cache key, so old art self-invalidates.

    uv run python -m wordplay_art.artwork portrait "a dragon wielding an axe" --style woodcut-ink
    uv run python -m wordplay_art.artwork tombstone dragon
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from . import presets
from .client import DEFAULT_HOST, DEFAULT_PORT, decode_image, generate

MODEL = "flux_2_klein_4b_q8p.ckpt"  # fallback default; the game passes its choice

# Selectable looks (the game's style dropdown). Each suffix — background included —
# is appended to a subject so the whole run stays coherent.
STYLES = {
    "storybook": "soft painterly storybook children's-book illustration, gouache "
        "texture, warm gentle colors, soft rounded shapes, whimsical, hand-drawn, "
        "friendly, plain soft cream background",
    "flat-sticker": "flat vector sticker illustration, bold clean black outlines, "
        "vibrant flat colors, plain white background",
    "enamel-pin": "glossy enamel pin game icon, thick gold metal outline, saturated "
        "colors, subtle gradient shading, plain white background",
    "pixel-art": "16-bit pixel art game sprite, crisp blocky pixels, limited retro "
        "palette, plain dark slate background",
    "woodcut-ink": "black and white woodcut engraving, bold ink linework, "
        "cross-hatching, high contrast, plain white background",
}
DEFAULT_STYLE = "storybook"

# Boon icons: a single evocative object per reward id (matches godot_version/core/boons.gd).
BOON_ICONS = {
    "tough": "a sturdy round shield with a heart emblem, symbol of toughness",
    "mend": "a glowing red healing potion bottle, symbol of mending",
    "focus": "a bright magnifying glass over a spark, symbol of focus and insight",
    "double": "two shining golden coins stacked, sparkling, symbol of doubled value",
}

NEGATIVE = (
    "text, words, letters, numbers, watermark, signature, frame, border, "
    "multiple characters, split panels, collage, photo, 3d render, blurry"
)

CACHE_ROOT = Path(__file__).resolve().parents[2] / ".cache" / "portraits"


# --- prompts -----------------------------------------------------------------
#
# One prompt template per KIND. Each takes a `subject` string (a creature noun, a
# weapon noun, a boon id) and returns a full styled prompt. Because monsters and
# weapons are drawn from their NOUN alone (no adjectives, no full sentence), a given
# creature/weapon caches once and is reused across every variant that carries it.

def _styled(subject: str, style: str) -> str:
    return f"{subject}, {STYLES.get(style, STYLES[DEFAULT_STYLE])}."


def _creature_prompt(creature: str, style: str) -> str:
    # Just the monster, no weapons — so the image caches per creature (a small,
    # fixed set) instead of per creature+weapon combo. The weapons are shown in the
    # UI as the letter tiles anyway.
    c = (creature or "creature").strip().lower()
    return _styled(f"a single full-body {c} monster character, centered", style)


def _boon_prompt(boon_id: str, style: str) -> str:
    return _styled(f"{BOON_ICONS.get(boon_id, boon_id)}, a single centered game icon, no background clutter", style)


def _tombstone_prompt(creature: str, style: str) -> str:
    c = (creature or "creature").strip().lower()
    return _styled(
        f"a weathered stone grave tombstone with a small sad {c} carved into it, "
        "a single centered grave marker", style)


PROMPTS = {
    "creature": _creature_prompt,
    "boon": _boon_prompt,
    "tombstone": _tombstone_prompt,
}


def build_prompt(kind: str, subject: str, style: str = DEFAULT_STYLE) -> str:
    if kind not in PROMPTS:
        raise ValueError("unknown art kind %r (have: %s)" % (kind, ", ".join(PROMPTS)))
    return PROMPTS[kind](subject, style)


# --- cache + generation engine (shared by portraits and boons) ---------------

def _sha(text: str, n: int) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:n]


def _paths(prompt: str, model: str) -> dict:
    """The on-disk png/meta paths for a prompt (content-addressed), plus the stable
    seed and resolved params. Paths need not exist yet."""
    seed = int(_sha(prompt, 8), 16)  # stable per prompt: same subject -> same image
    params = presets.resolve(model)
    key = {"model": model, "params": params, "seed": seed, "negative": NEGATIVE}
    folder = CACHE_ROOT / model / _sha(json.dumps(key, sort_keys=True), 12)
    return {
        "prompt": prompt, "seed": seed, "params": params,
        "png": folder / f"{_sha(prompt, 16)}.png", "meta": folder / f"{_sha(prompt, 16)}.json",
    }


def _render(prompt: str, model: str, meta: dict, *, host: str, port: int, regenerate: bool) -> Path:
    """Return the cached image for `prompt`, generating it (Draw Things) if missing."""
    p = _paths(prompt, model)
    png: Path = p["png"]
    if png.exists() and not regenerate:
        return png
    imgs = generate(prompt=prompt, model=model, host=host, port=port,
                    negative_prompt=NEGATIVE, seed=p["seed"])
    if not imgs:
        raise RuntimeError("Draw Things returned no image")
    png.parent.mkdir(parents=True, exist_ok=True)
    decode_image(imgs[0]).save(png)
    p["meta"].write_text(json.dumps(
        {**meta, "prompt": prompt, "model": model, "seed": p["seed"],
         "params": p["params"], "negative": NEGATIVE}, indent=2))
    return png


# --- public API (one call for every kind) ------------------------------------

def cached_path(kind: str, subject: str, style: str = DEFAULT_STYLE, model: str = MODEL) -> Path | None:
    png = _paths(build_prompt(kind, subject, style), model)["png"]
    return png if png.exists() else None


def image(kind: str, subject: str, *, style: str = DEFAULT_STYLE, model: str = MODEL,
          host: str = DEFAULT_HOST, port: int = DEFAULT_PORT, regenerate: bool = False) -> Path:
    """The cached artwork for (kind, subject, style, model), generating if missing."""
    return _render(build_prompt(kind, subject, style), model,
                   {"kind": kind, "subject": subject, "style": style},
                   host=host, port=port, regenerate=regenerate)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Generate/cache one piece of styled artwork.")
    p.add_argument("kind", choices=sorted(PROMPTS), help="what to draw")
    p.add_argument("subject", help="the subject noun / id (e.g. dragon, axe, tough)")
    p.add_argument("--style", default=DEFAULT_STYLE, choices=sorted(STYLES))
    p.add_argument("--model", default=MODEL)
    p.add_argument("--port", type=int, default=DEFAULT_PORT, help="Draw Things gRPC port")
    p.add_argument("--regenerate", action="store_true")
    p.add_argument("--print-prompt", action="store_true")
    a = p.parse_args(argv)
    if a.print_prompt:
        print(build_prompt(a.kind, a.subject, a.style))
        return 0
    print(image(a.kind, a.subject, style=a.style, model=a.model, port=a.port, regenerate=a.regenerate))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
