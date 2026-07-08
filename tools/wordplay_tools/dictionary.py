"""Build the in-game validation word list.

The letter-pool game only needs to answer one thing about a typed word: is it
real? So this builds a plain sorted word list once, at build time (part-of-speech
and sentiment used to be stored too, but the pool mechanic doesn't use them).

Source: WordNet for the word set, plus our curated lexicon (lexicon.py) so the
core game vocabulary is always accepted.

Run via the console script:  ``wordplay-dictionary``  (see pyproject.toml).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from . import lexicon

# Keep words short enough to be gameable and the file small.
MIN_LEN = 3
MAX_LEN = 9

_DEFAULT_OUT = (
    Path(__file__).resolve().parents[2] / "game" / "data" / "dictionary.json"
)


def _curated_words() -> set[str]:
    """Words our lexicon already uses (creatures/items/adjectives), so they're always
    valid to type even if WordNet misses one."""
    game_kinds = {lexicon.KIND_CREATURE, lexicon.KIND_ITEM, lexicon.KIND_ADJ}
    return {w for w, meta in lexicon.word_index().items() if meta["kind"] in game_kinds}


def build_dictionary() -> list[str]:
    """The set of real, gameable words — membership only. The letter-pool game just
    needs 'is this a word?', so we no longer store part-of-speech or sentiment (they
    were vestigial from the old ladder mechanic, and dropping them shrinks the file
    ~5x)."""
    from nltk.corpus import wordnet as wn

    words: set[str] = set()
    for lemma in wn.all_lemma_names():
        if not lemma.isalpha() or not lemma.islower():
            continue
        if not (MIN_LEN <= len(lemma) <= MAX_LEN):
            continue
        if wn.synsets(lemma):
            words.add(lemma)

    words |= _curated_words()
    return sorted(words)


def write_dictionary(out_path: Path) -> dict:
    words = build_dictionary()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 2,
        "min_len": MIN_LEN,
        "max_len": MAX_LEN,
        "count": len(words),
        "words": words,
    }
    out_path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build the validation dictionary.")
    parser.add_argument("-o", "--out", type=Path, default=_DEFAULT_OUT)
    args = parser.parse_args(argv)

    payload = write_dictionary(args.out)
    words = set(payload["words"])
    size_kb = args.out.stat().st_size / 1024
    print(f"Wrote {args.out}  ({payload['count']} words, {size_kb:.0f} KB)")
    for w in ["dragon", "darn", "road", "fine", "knife", "nag", "adorn", "gore"]:
        print(f"  {w:8} -> {'ok' if w in words else 'NOT FOUND'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
