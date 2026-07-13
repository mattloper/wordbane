"""Build the checked-in emoji vocabulary: emoji -> {name, keywords}.

Source is the `emoji` package's CLDR-derived data (English names + aliases), enriched
with the Unicode character name. We keep one representative per emoji, skip skin-tone and
flag noise, and sort the output so the file diffs cleanly. Rerun only when you want to
pull in new emoji or better keywords; the game never reads this file directly.

    uv run python -m wordbane_emoji.vocab
"""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

import emoji as emoji_pkg

VOCAB_PATH = Path(__file__).resolve().parent.parent / "data" / "emoji_vocab.json"

# Emoji we never want as a game bonk: skin-tone modifiers, regional-indicator flags,
# and keycap/subdivision bits that only make sense in combination.
_SKIP_NAME = re.compile(r"skin tone|flag|regional indicator|keycap|tag ", re.I)


def _tokens(text: str) -> list[str]:
    return [t for t in re.split(r"[^a-z0-9]+", text.lower()) if len(t) > 1]


def build_vocab() -> dict:
    out: dict[str, dict] = {}
    for ch, data in emoji_pkg.EMOJI_DATA.items():
        # Only fully-qualified, single-status emoji; skip variants/sequences we can't draw.
        if data.get("status") != emoji_pkg.STATUS["fully_qualified"]:
            continue
        name = data.get("en", "").strip(":").replace("_", " ")
        if not name or _SKIP_NAME.search(name):
            continue
        # Keywords: the alias slugs + the Unicode name, deduped, order-stable.
        kw: list[str] = []
        for alias in data.get("alias", []):
            kw += _tokens(alias.strip(":").replace("_", " "))
        try:
            kw += _tokens(unicodedata.name(ch[0]))
        except (ValueError, IndexError):
            pass
        kw += _tokens(name)
        seen, keywords = set(), []
        for t in kw:
            if t not in seen:
                seen.add(t)
                keywords.append(t)
        # First emoji wins for a given name, so the vocab is stable and one-per-concept.
        if name not in {v["name"] for v in out.values()}:
            out[ch] = {"name": name, "keywords": keywords}
    return dict(sorted(out.items()))


def main() -> None:
    vocab = build_vocab()
    VOCAB_PATH.parent.mkdir(parents=True, exist_ok=True)
    VOCAB_PATH.write_text(
        json.dumps(vocab, ensure_ascii=False, indent=1, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(vocab)} emoji -> {VOCAB_PATH}")


if __name__ == "__main__":
    main()
